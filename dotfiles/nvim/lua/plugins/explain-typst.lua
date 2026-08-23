-- Typst -> LaTeX convert-on-insert for explanation buffers.
--
-- Questions are typed with terse Typst math (`integral_0^1 x^2 dif x`), but
-- the explanation documents must stay pure LaTeX (`$...$` inline, `$$...$$`
-- display -- the delimiters the renderer understands). `<localleader>t`
-- converts in place through tylax's `t2l` CLI (pkgs/tylax):
--
--   visual charwise  selection is one math snippet -> `$<latex>$`
--   visual linewise  selection is one math snippet -> `$$<latex>$$`
--   normal           the inline `$...$` region under the cursor, in place
--
-- The snippet may or may not already carry `$` delimiters; bare text is
-- wrapped before conversion because t2l otherwise parses it as Typst markup.
-- On any converter failure the buffer is left untouched.
--
-- Not a plugin: like plugins/explain.lua this registers a FileType autocmd at
-- startup and returns an empty spec list. It activates per buffer, only when
-- walking upward from the buffer's file finds `.explain.json`, and stays
-- independent of explain.lua (same root discovery, no shared state).

local function find_root(file)
  if file == "" then
    return nil
  end
  local marker = vim.fs.find(".explain.json", { path = vim.fs.dirname(file), upward = true })[1]
  return marker and vim.fs.dirname(marker) or nil
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Explain" })
end

--- Run `t2l` synchronously on Typst source.
---@return string|nil out, string|nil err
local function run_t2l(text)
  -- Direction forced: auto-detection on terse math snippets is unreliable.
  local ok, proc = pcall(vim.system, { "t2l", "--direction", "t2l" }, { stdin = text, text = true })
  if not ok then
    return nil, "could not start t2l: " .. tostring(proc)
  end
  local res = proc:wait(10000)
  if res.code ~= 0 then
    local detail = vim.trim(res.stderr or "")
    return nil, ("t2l exited %d%s"):format(res.code, detail ~= "" and ": " .. detail or "")
  end
  if vim.trim(res.stdout or "") == "" then
    return nil, "t2l produced no output"
  end
  return res.stdout, nil
end

--- Convert one Typst math snippet (with or without surrounding `$`) and
--- return replacement lines: `$<latex>$` for style "inline", `$$<latex>$$`
--- for style "display".
---@return string[]|nil lines, string|nil err
local function convert_math(snippet, style)
  local trimmed = vim.trim(snippet)
  local unwrapped = trimmed:match("^%$(.*)%$$")
  local inner = vim.trim(unwrapped or trimmed)
  if inner == "" then
    return nil, "empty math snippet"
  end
  if not unwrapped and trimmed:find("%$") then
    return nil, "selection mixes text and $math$; select just the math"
  end
  -- Typst `$x$` (no inner padding) converts to inline LaTeX `$...$`; padded
  -- `$ x $` would convert to display `\[...\]` instead.
  local out, err = run_t2l("$" .. inner .. "$")
  if not out then
    return nil, err
  end
  local core = vim.trim(out)
  core = core:match("^%$(.*)%$$") or core:match("^\\%[%s*(.-)%s*\\%]$") or core
  core = vim.trim(core)
  if core == "" then
    return nil, "t2l produced no output"
  end
  if style == "display" then
    local lines = vim.split(core, "\n", { plain = true })
    if #lines == 1 then
      return { "$$" .. core .. "$$" }
    end
    table.insert(lines, 1, "$$")
    table.insert(lines, "$$")
    return lines
  end
  return { "$" .. core:gsub("%s*\n%s*", " ") .. "$" }
end

local function editable(bufnr)
  if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
    notify("Buffer is not modifiable (READ mode or submit running?)", vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Convert the visual selection in place. Register-free (clipboard is
--- unnamedplus): the region is read with getregion() and replaced with
--- nvim_buf_set_text/set_lines. On failure the selection stays active and
--- the text untouched.
local function convert_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local mode = vim.fn.mode()
  if mode == "\22" then
    notify("Blockwise selection is not supported", vim.log.levels.WARN)
    return
  end
  if not editable(bufnr) then
    return
  end

  local vpos, cpos = vim.fn.getpos("v"), vim.fn.getpos(".")
  local lines = vim.fn.getregion(vpos, cpos, { type = mode })
  local region = vim.fn.getregionpos(vpos, cpos, { type = mode })
  if #lines == 0 or #region == 0 then
    return
  end

  local out, err = convert_math(table.concat(lines, "\n"), mode == "V" and "display" or "inline")
  if not out then
    notify("Typst -> LaTeX failed: " .. err, vim.log.levels.ERROR)
    return
  end

  local first, last = region[1][1], region[#region][2]
  if mode == "V" then
    vim.api.nvim_buf_set_lines(bufnr, first[2] - 1, last[2], true, out)
  else
    -- getregionpos columns are 1-based inclusive bytes; set_text wants
    -- 0-based start and exclusive end.
    vim.api.nvim_buf_set_text(bufnr, first[2] - 1, first[3] - 1, last[2] - 1, last[3], out)
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

--- Convert the inline `$...$` region under the cursor, delimiters included.
local function convert_inline()
  local bufnr = vim.api.nvim_get_current_buf()
  if not editable(bufnr) then
    return
  end
  local line = vim.api.nvim_get_current_line()
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  local col = col0 + 1 -- 1-based byte column

  -- Unescaped `$` positions on the line.
  local dollars = {}
  local i = 1
  while true do
    local s = line:find("%$", i)
    if not s then
      break
    end
    if line:sub(s - 1, s - 1) ~= "\\" then
      table.insert(dollars, s)
    end
    i = s + 1
  end

  -- Pair them up and pick the non-empty span containing the cursor.
  local span
  for k = 1, #dollars - 1, 2 do
    local s, e = dollars[k], dollars[k + 1]
    if e > s + 1 and col >= s and col <= e then
      span = { s, e }
      break
    end
  end
  if not span then
    notify("No inline $...$ region under the cursor", vim.log.levels.WARN)
    return
  end

  local out, err = convert_math(line:sub(span[1], span[2]), "inline")
  if not out then
    notify("Typst -> LaTeX failed: " .. err, vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_buf_set_text(bufnr, row - 1, span[1] - 1, row - 1, span[2], out)
end

local function attach(bufnr)
  if vim.b[bufnr].explain_typst_attached then
    return
  end
  if not find_root(vim.api.nvim_buf_get_name(bufnr)) then
    return
  end
  vim.b[bufnr].explain_typst_attached = true
  local map = vim.keymap.set
  map("x", "<localleader>t", convert_selection, { buffer = bufnr, desc = "Explain: Typst selection -> LaTeX" })
  map("n", "<localleader>t", convert_inline, { buffer = bufnr, desc = "Explain: Typst $...$ -> LaTeX" })
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("explain-typst", { clear = true }),
  pattern = "markdown",
  callback = function(ev)
    attach(ev.buf)
  end,
})

return {}
