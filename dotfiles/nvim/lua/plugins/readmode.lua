-- Read mode for rendered Markdown (issue #11). Explanation documents are
-- mostly read, not edited, but the rendering stack is tuned for editing:
-- render-markdown's anti-conceal re-opens the cursor line and render-latex
-- reveals the raw TeX of any display equation the cursor rests on. In READ
-- mode the buffer stays fully rendered while scrolling with the cursor:
--
-- - render-markdown: anti-conceal off, concealcursor=nvc (per-buffer, by
--   mutating the plugin's cached buffer config -- it has no runtime
--   per-buffer API; the fields are read live on every update).
-- - render-latex: rc4 hard-wires cursor reveal (renderer.sync_focus), so the
--   cursor is hopped over display-equation blocks instead; it never rests
--   inside one, and the image never opens. Uses only the public
--   current_equation() API.
-- - Snacks.image inline math respects concealcursor and keeps its images.
-- - The buffer is made non-modifiable as an edit guard.
--
-- :ReadMode (or <localleader>r) toggles; EDIT restores exactly the previous
-- behaviour. Buffers inside an explanation tree (a `.explain.json` root, same
-- marker plugins/explain.lua walks to) open in READ mode by default.
--
-- Not a plugin: registers autocmds/commands and returns an empty spec list.

local group = vim.api.nvim_create_augroup("markdown-read-mode", { clear = true })

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

local function set_read_mode(buf, on)
  if vim.b[buf].read_mode == on then
    return
  end
  vim.b[buf].read_mode = on

  local cfg = rm_config(buf)
  if on then
    if cfg then
      vim.b[buf].read_mode_saved = {
        anti_conceal = cfg.anti_conceal.enabled,
        concealcursor = cfg.win_options.concealcursor
          and cfg.win_options.concealcursor.rendered,
        modifiable = vim.bo[buf].modifiable,
      }
      cfg.anti_conceal.enabled = false
      cfg.win_options.concealcursor = cfg.win_options.concealcursor
        or { default = vim.o.concealcursor }
      cfg.win_options.concealcursor.rendered = "nvc"
    end
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
    vim.bo[buf].modifiable = saved.modifiable ~= false and true or false
    vim.api.nvim_clear_autocmds({ group = group, buffer = buf, event = "CursorMoved" })
    vim.b[buf].read_mode_saved = nil
  end
  rm_refresh(buf)
  vim.notify("Markdown " .. (on and "READ" or "EDIT") .. " mode", vim.log.levels.INFO)
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

return {}
