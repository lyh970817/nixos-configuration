-- Read mode for rendered Markdown (issue #11). Explanation documents are
-- mostly read, not edited, but the rendering stack is tuned for editing:
-- render-markdown's anti-conceal re-opens the cursor line and render-latex
-- reveals the raw TeX of any display equation the cursor rests on. In READ
-- mode the buffer stays fully rendered while scrolling with the cursor:
--
-- - render-markdown: anti-conceal off, concealcursor=nvc (per-buffer, by
--   mutating the plugin's cached buffer config -- it has no runtime
--   per-buffer API; the fields are read live on every update).
-- - render-latex: rc4 hard-wires cursor reveal (renderer.sync_focus runs
--   unconditionally in the render path and config.lua has no knob for it), so
--   the cursor is hopped over display-equation blocks instead; it never rests
--   inside one, and the image never opens. Uses only the public
--   current_equation() API.
-- - Snacks.image inline math respects concealcursor and keeps its images.
-- - The buffer is made non-modifiable as an edit guard.
-- - Long lines soft-wrap to the window (wrap/linebreak/breakindent), set
--   directly per window: render-markdown's win_options channel only manages
--   conceal* here, so nothing fights a plain setlocal. Wrap is skipped when
--   the buffer holds a pipe-table row wider than the window: wrapping such a
--   row shatters the rendered table (see wrap_breaks_table), and wrapping
--   WITHIN cells has no supported implementation -- render-markdown's cell
--   wrapping is an open request (its issue #616), and the one plugin doing
--   it (ice345/markdown-table-wrap.nvim) needs render-markdown's table
--   renderer disabled and itself recommends nowrap for its inline mode.
--
-- Surveyed alternatives (2026-08) before keeping this custom:
-- - render-markdown has no supported runtime per-buffer config API: the
--   api.render({buf, config}) custom config only applies on first attach
--   (state.get ignores it once the buffer config is cached) and
--   overrides.* resolve at attach time, so the cache mutation stays. Its own
--   api.expand/contract mutate the same cached fields.
-- - Snacks.zen/zoom (and zen-mode.nvim etc.) are floating-window overlays;
--   render-latex clears every equation image while any floating window is
--   open (set_suppressed("floating", ...)), so zen blanks the math this mode
--   exists to keep visible.
-- - :RenderMarkdown preview mirrors into a scratch split (not an in-place
--   toggle) and does nothing about render-latex's cursor reveal.
-- - glow.nvim/markdown-preview.nvim render outside the buffer and lose the
--   render-latex/Snacks.image stack entirely.
--
-- :ReadMode (or <localleader>r) toggles; EDIT restores exactly the previous
-- behaviour. Buffers inside an explanation tree (a `.explain.json` root, same
-- marker plugins/explain.lua walks to) open in READ mode by default.
--
-- Not a plugin: registers autocmds/commands and returns an empty spec list.

local group = vim.api.nvim_create_augroup("markdown-read-mode", { clear = true })

-- Window-local READ-mode options: soft-wrap long lines to the window width.
local read_win_options = { wrap = true, linebreak = true, breakindent = true }

--- Apply window-local options in every window showing the buffer.
---@param buf integer
---@param values table<string, boolean>
local function apply_win_options(buf, values)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    for name, value in pairs(values) do
      vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
    end
  end
end

--- True when a pipe-table row is wider than the window's text area. 'wrap'
--- is window-local (no per-line exception exists), and Neovim decides break
--- points on the raw text before conceal, so one over-wide row wraps
--- mid-table and shatters the rendered borders (render-markdown
--- doc/limitations.md, its issue #82, neovim/neovim#14409). Narrow tables
--- are unaffected by wrap, so only over-wide rows suppress it.
---@param buf integer
---@param win? integer
local function wrap_breaks_table(buf, win)
  if not win then
    return false
  end
  local width = vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^%s*|") and vim.fn.strdisplaywidth(line) > width then
      return true
    end
  end
  return false
end

--- render-markdown's cached per-buffer config, or nil.
local function rm_config(buf)
  local ok, state = pcall(require, "render-markdown.state")
  if not ok then
    return nil
  end
  local ok2, cfg = pcall(state.get, buf)
  return ok2 and cfg or nil
end

--- Force render-markdown to redraw the buffer in every window showing it.
local function rm_refresh(buf)
  pcall(function()
    local ui = require("render-markdown.core.ui")
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      ui.update(buf, win, "ReadMode", true)
    end
  end)
end

--- Move the cursor off the display equation it just landed on, in the
--- direction it was travelling, so render-latex never reveals raw TeX.
local function hop_off_equation(buf)
  local ok, renderer = pcall(require, "render_latex.renderer")
  if not ok then
    return
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    return
  end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local last = vim.b[buf].read_mode_last_row or row
  local eq_ok, eq = pcall(renderer.current_equation, buf)
  if eq_ok and eq ~= nil then
    -- eq rows are 0-indexed: line above is start_row, line below end_row + 2.
    local before, after = eq.start_row, eq.end_row + 2
    local last_line = vim.api.nvim_buf_line_count(buf)
    local target = row >= last and after or before
    if target < 1 then
      target = after
    end
    if target > last_line then
      target = before
    end
    if target >= 1 and target <= last_line and target ~= row then
      vim.api.nvim_win_set_cursor(win, { target, 0 })
      row = target
    end
  end
  vim.b[buf].read_mode_last_row = row
end

local function set_read_mode(buf, on, opts)
  opts = opts or {}
  if vim.b[buf].read_mode == on then
    return
  end
  -- plugins/explain.lua freezes explanation buffers while explainctl rewrites
  -- the tree; flipping modifiable underneath that lock would corrupt the
  -- options it restores when the run finishes.
  if vim.b[buf].explain_submit_lock then
    vim.notify("Buffer is frozen by a running explain submit", vim.log.levels.WARN)
    return
  end
  vim.b[buf].read_mode = on

  local cfg = rm_config(buf)
  if on then
    -- Previous wrap options, from the first window showing the buffer (the
    -- toggling one in practice); global values for a windowless buffer.
    local win = vim.fn.win_findbuf(buf)[1]
    local opt_src = win and vim.wo[win] or vim.o
    local saved_win = {}
    for name in pairs(read_win_options) do
      saved_win[name] = opt_src[name]
    end
    vim.b[buf].read_mode_saved = {
      anti_conceal = cfg and cfg.anti_conceal.enabled,
      concealcursor = cfg
        and cfg.win_options.concealcursor
        and cfg.win_options.concealcursor.rendered,
      modifiable = vim.bo[buf].modifiable,
      win_options = saved_win,
    }
    if cfg then
      cfg.anti_conceal.enabled = false
      cfg.win_options.concealcursor = cfg.win_options.concealcursor
        or { default = vim.o.concealcursor }
      cfg.win_options.concealcursor.rendered = "nvc"
    end
    local read_opts = vim.tbl_extend("force", {}, read_win_options)
    if wrap_breaks_table(buf, win) then
      read_opts.wrap = false
      vim.b[buf].read_mode_wrap_suppressed = true
    end
    apply_win_options(buf, read_opts)
    vim.bo[buf].modifiable = false
    vim.b[buf].read_mode_last_row = nil
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = group,
      buffer = buf,
      callback = function(ev)
        if vim.b[ev.buf].read_mode then
          hop_off_equation(ev.buf)
        end
      end,
    })
    hop_off_equation(buf)
  else
    local saved = vim.b[buf].read_mode_saved or {}
    if cfg then
      cfg.anti_conceal.enabled = saved.anti_conceal ~= false and true or false
      if cfg.win_options.concealcursor then
        cfg.win_options.concealcursor.rendered = saved.concealcursor or ""
      end
    end
    local restore = {}
    for name in pairs(read_win_options) do
      restore[name] = saved.win_options and saved.win_options[name] == true or false
    end
    apply_win_options(buf, restore)
    vim.bo[buf].modifiable = saved.modifiable ~= false and true or false
    vim.api.nvim_clear_autocmds({ group = group, buffer = buf, event = "CursorMoved" })
    vim.b[buf].read_mode_saved = nil
    vim.b[buf].read_mode_wrap_suppressed = nil
  end
  rm_refresh(buf)
  -- Toggling wrap shifts screen rows; rc4 re-places equation images only on
  -- its own events, so the next one would otherwise leave them blank.
  pcall(function()
    require("render_latex.renderer").queue(buf)
  end)
  if not opts.silent then
    local msg = "Markdown " .. (on and "READ" or "EDIT") .. " mode"
    if on and vim.b[buf].read_mode_wrap_suppressed then
      msg = msg .. " (no wrap: table wider than window)"
    end
    vim.notify(msg, vim.log.levels.INFO)
  end
end

local function toggle(buf)
  set_read_mode(buf, not vim.b[buf].read_mode)
end

--- True when the buffer's file lives in an explanation tree (mirrors
--- plugins/explain.lua's root discovery).
local function in_explanation_tree(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    return false
  end
  local marker = vim.fs.find(".explain.json", { path = vim.fs.dirname(file), upward = true })[1]
  return marker ~= nil
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = function(ev)
    vim.api.nvim_buf_create_user_command(ev.buf, "ReadMode", function()
      toggle(ev.buf)
    end, { desc = "Toggle rendered read mode (no cursor reveal)" })
    vim.keymap.set("n", "<localleader>r", function()
      toggle(ev.buf)
    end, { buffer = ev.buf, desc = "Toggle read mode" })

    -- Explanation documents open reading-first. Deferred so render-markdown
    -- and render-latex have attached before their config is touched.
    if in_explanation_tree(ev.buf) then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(ev.buf) and not vim.b[ev.buf].read_mode then
          set_read_mode(ev.buf, true)
        end
      end)
    end
  end,
})

-- Programmatic API for other config modules (plugins/explain.lua switches to
-- EDIT before writing question blocks and restores READ after a submit).
-- Seeded into package.loaded directly: lazy.nvim owns require("plugins.*")
-- for specs, and this file's spec-list return value must stay a plain list.
local M = {}

--- Whether the buffer is currently in READ mode.
function M.is_read(buf)
  return vim.b[buf].read_mode == true
end

--- Switch a buffer to "read" or "edit" through the same path as :ReadMode,
--- keeping the saved per-buffer state consistent. opts.silent skips the
--- mode-change notification.
function M.set_mode(buf, mode, opts)
  assert(mode == "read" or mode == "edit", "mode must be 'read' or 'edit'")
  set_read_mode(buf, mode == "read", opts)
end

package.loaded["markdown-readmode"] = M

return {}
