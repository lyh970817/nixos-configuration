-- Browser preview for explanation workspaces, via live-preview.nvim.
--
-- The in-terminal rendering stack (plugins/markdown.lua, plugins/snacks.lua)
-- stays the fallback; this serves the explanation tree over HTTP instead --
-- client-side markdown-it + KaTeX with websocket live updates and scroll sync
-- -- and puts a browser tab in front of the human wherever they are looking:
-- pushed to the laptop over SSH when the viewer is remote, opened locally
-- otherwise. Network decisions (bind address, port, dispatch) live in the
-- `explain-preview` script (home/programs/explain-preview.nix); this side
-- only asks it and drives the plugin.
--
-- The plugin source is Nix-vendored under vendor/ (same mechanism as
-- render-markdown.nvim in plugins/markdown.lua): the nixpkgs pin needs a
-- patch -- its Server:start ends in vim.uv.run(), which wedges the editor's
-- main loop -- and lazy.nvim cannot fetch a patched tree itself.
--
-- Activation is deliberate, not ambient: a tab opens only in the dedicated
-- explain Neovim (EXPLAIN_ORIGIN_SESSION_ID set by herdr-explain-current),
-- after :ExplainOpenRoot, or on :ExplainPreview. Once active for a root,
-- every buffer under it gets its own tab, opened once per file per session
-- (the plugin routes updates and scroll messages per file, so children live
-- in tabs of their own; plain buffer switching never spawns duplicates).
-- Typst-canonical trees (`"math_syntax": "typst"` in .explain.json) opt out
-- of the automatic paths entirely -- KaTeX cannot render Typst math -- and
-- open only on an explicit :ExplainPreview.
--
-- Like plugins/explain.lua this file is not a plugin itself: it registers
-- autocmds at import time, seeds package.loaded for the cross-file hook in
-- explain.lua, and returns the lazy spec for the vendored plugin.

---------------------------------------------------------------------------
-- Root discovery (same `.explain.json` walk as explain.lua and readmode.lua)
---------------------------------------------------------------------------

---@param file string absolute file path
---@return string|nil
local function find_root(file)
  if file == "" then
    return nil
  end
  local marker = vim.fs.find(".explain.json", { path = vim.fs.dirname(file), upward = true })[1]
  return marker and vim.fs.dirname(marker) or nil
end

--- Whether the tree's `.explain.json` declares Typst-canonical math. The
--- preview renders with KaTeX, which cannot read Typst, so these trees are
--- excluded from every automatic open below; :ExplainPreview stays available
--- for whoever wants the (math-less) rendering anyway. A plain string probe,
--- not a JSON parse: the marker is machine-written verbatim by explainctl.
---@param root string
---@return boolean
local function typst_tree(root)
  local fd = io.open(root .. "/.explain.json", "r")
  if not fd then
    return false
  end
  local text = fd:read("*a") or ""
  fd:close()
  return text:find('"math_syntax"%s*:%s*"typst"') ~= nil
end

local function buf_file(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name ~= "" and vim.fn.fnamemodify(name, ":p") or ""
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Explain preview" })
end

---------------------------------------------------------------------------
-- Server and browser-tab state
---------------------------------------------------------------------------

local M = {}

local state = {
  info = nil, -- { address, port } from `explain-preview info`, cached per session
  root = nil, -- explanation root the running server serves
  activated = {}, -- [root] = true once the preview follows this tree
  opened = {}, -- [file] = true once a browser tab was opened for it
}

--- Bind address and port from the Nix-side dispatcher.
---@return { address: string, port: integer }|nil
local function preview_info()
  if state.info then
    return state.info
  end
  local ok, res = pcall(function()
    return vim.system({ "explain-preview", "info" }, { text = true }):wait(4000)
  end)
  if not ok or res.code ~= 0 then
    notify("explain-preview info failed; no browser preview", vim.log.levels.ERROR)
    return nil
  end
  local address, port = (res.stdout or ""):match("^(%S+)%s+(%d+)")
  if not address then
    notify("explain-preview info returned garbage; no browser preview", vim.log.levels.ERROR)
    return nil
  end
  state.info = { address = address, port = tonumber(port) }
  return state.info
end

--- Start (or reuse) the in-editor preview server rooted at `root`. One server
--- per Neovim instance; switching to a different explanation tree restarts it
--- there, which drops any tabs of the old tree.
---@return boolean ok
local function ensure_server(root)
  local info = preview_info()
  if not info then
    return false
  end
  -- The vendored plugin is lazy (`lazy = true` below): ordinary sessions
  -- never load it. Outside lazy (scratch tests) the vendor path is on the
  -- runtimepath directly, so the plain require works either way.
  pcall(function()
    require("lazy").load({ plugins = { "live-preview.nvim" } })
  end)
  local ok, lp = pcall(require, "livepreview")
  if not ok then
    notify("live-preview.nvim is not available", vim.log.levels.ERROR)
    return false
  end
  if state.root == root and lp.is_running() then
    return true
  end
  require("livepreview.config").set({
    address = info.address,
    port = info.port,
    -- dynamic_root makes the server's webroot the started file's directory:
    -- only this explanation tree is exposed on the unauthenticated tailnet
    -- port, mirroring html-open's narrow rooting.
    dynamic_root = true,
  })
  -- start() uses the path only for its dirname (the webroot) and extension
  -- (markdown update mode); the root document need not exist yet.
  lp.start(root .. "/explanation.md", info.port)
  state.root = root
  state.opened = {}
  return true
end

--- Open the browser tab for one file (dispatch decides which machine).
local function open_tab(file, root)
  local info = state.info
  local rel = file:sub(#root + 2)
  local url = ("http://%s:%d/%s"):format(info.address, info.port, vim.uri_encode(rel))
  vim.system({ "explain-preview", "open", url }, { text = true }, function(res)
    if res.code ~= 0 then
      vim.schedule(function()
        notify("Could not open the preview tab: " .. vim.trim(res.stderr or ""), vim.log.levels.WARN)
      end)
    end
  end)
end

local function active_for(root)
  -- The dedicated explain Neovim (F7 flow) previews every tree it opens.
  local env = vim.env.EXPLAIN_ORIGIN_SESSION_ID
  return state.activated[root] or (env ~= nil and env ~= "")
end

--- Preview a buffer's file: server up, tab open (once per file unless forced).
---@param force boolean reopen the tab even if one was opened before
function M.preview(bufnr, force)
  local file = buf_file(bufnr)
  local root = find_root(file)
  if not root then
    return
  end
  -- Ambient/auto callers (attach below, explain.lua's :ExplainOpenRoot hook)
  -- pass force=false and are skipped for Typst-canonical trees; only the
  -- explicit :ExplainPreview (force=true) goes through.
  if not force and typst_tree(root) then
    return
  end
  state.activated[root] = true
  if not ensure_server(root) then
    return
  end
  if force or not state.opened[file] then
    state.opened[file] = true
    open_tab(file, root)
  end
end

---------------------------------------------------------------------------
-- Per-buffer activation
---------------------------------------------------------------------------

local function attach(bufnr)
  if vim.b[bufnr].explain_preview_attached then
    return
  end
  local file = buf_file(bufnr)
  local root = find_root(file)
  if not root then
    return
  end
  vim.b[bufnr].explain_preview_attached = true

  -- External-change reload: explainctl, sync agents, and the peer host all
  -- rewrite these files behind Neovim's back, and the preview pushes to the
  -- browser from the buffer (the plugin's TextChanged hook -- verified to
  -- fire on a checktime autoread reload). 'autoread' is explicit rather than
  -- assumed, and the triggers are scoped to explanation buffers so ordinary
  -- files keep stock behavior. explain.lua's post-submit checktime covers
  -- the submit path; these cover everything else. silent!: checktime is
  -- forbidden in a few contexts (cmdline window) and a missed poll is fine.
  vim.o.autoread = true
  vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold", "CursorHoldI" }, {
    group = vim.api.nvim_create_augroup("explain-preview-reload-" .. bufnr, { clear = true }),
    buffer = bufnr,
    callback = function()
      vim.cmd("silent! checktime " .. bufnr)
    end,
  })

  vim.api.nvim_buf_create_user_command(bufnr, "ExplainPreview", function()
    M.preview(bufnr, true)
  end, { desc = "Open (or reopen) the browser preview tab for this document" })

  if active_for(root) then
    M.preview(bufnr, false)
  end
end

local group = vim.api.nvim_create_augroup("explain-preview", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = function(ev)
    attach(ev.buf)
  end,
})

-- Seeded into package.loaded directly: lazy.nvim owns require("plugins.*"),
-- and explain.lua's :ExplainOpenRoot hook needs a stable module name.
package.loaded["explain-preview"] = M

---------------------------------------------------------------------------
-- Vendored plugin spec
---------------------------------------------------------------------------

return {
  {
    "brianhuster/live-preview.nvim",
    -- Vendored: nixpkgs pin plus the uv.run() removal, applied as a Nix
    -- patch -- see home/programs/explain-preview.nix, which symlinks the
    -- patched source here. Drop the dir override (and the Nix block) when
    -- the nixpkgs pin moves past the upstream fix.
    dir = vim.fn.stdpath("config") .. "/vendor/live-preview.nvim",
    name = "live-preview.nvim",
    -- Loaded on demand by ensure_server above; ordinary Markdown sessions
    -- never pay for it.
    lazy = true,
  },
}
