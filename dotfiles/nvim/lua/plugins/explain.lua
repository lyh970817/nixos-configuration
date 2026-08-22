-- Explanation-workspace UI for the forked Claude explanation sessions
-- (nixos-configuration issue #11, phases 3/4).
--
-- Not a plugin: this file registers autocmds at startup (lazy.nvim imports it
-- eagerly) and returns an empty spec list. The UI activates per buffer, and
-- only when walking upward from the buffer's file finds `.explain.json` -- the
-- marker `explainctl` writes at every explanation root. Ordinary Markdown
-- buffers are untouched.
--
-- The durable state is the Markdown tree; `explainctl` owns locking, session
-- resume, and snapshots. This side only inserts question blocks, saves and
-- freezes buffers around a submit, and applies the JSON result.

---------------------------------------------------------------------------
-- Root discovery
---------------------------------------------------------------------------

--- Walk upward from a file to the explanation root (directory containing
--- `.explain.json`), or nil when the file is not part of an explanation tree.
---@param file string absolute file path
---@return string|nil
local function find_root(file)
  if file == "" then
    return nil
  end
  local marker = vim.fs.find(".explain.json", { path = vim.fs.dirname(file), upward = true })[1]
  return marker and vim.fs.dirname(marker) or nil
end

--- Absolute path of a buffer's file, or "" for unnamed buffers.
local function buf_file(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name ~= "" and vim.fn.fnamemodify(name, ":p") or ""
end

--- Loaded, file-backed buffers whose files live under `root`.
---@return integer[]
local function buffers_under(root)
  local prefix = root .. "/"
  local bufs = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
      local file = buf_file(buf)
      if file ~= "" and vim.startswith(file, prefix) then
        table.insert(bufs, buf)
      end
    end
  end
  return bufs
end

local function read_metadata(root)
  local fd = io.open(root .. "/.explain.json", "r")
  if not fd then
    return nil
  end
  local text = fd:read("*a")
  fd:close()
  local ok, meta = pcall(vim.json.decode, text)
  return ok and type(meta) == "table" and meta or nil
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Explain" })
end

--- plugins/readmode.lua's mode API (is_read/set_mode), or nil before that
--- file has loaded. Going through set_mode instead of setting 'modifiable'
--- keeps readmode's saved per-buffer state consistent.
local function readmode()
  local ok, mod = pcall(require, "markdown-readmode")
  return ok and mod or nil
end

---------------------------------------------------------------------------
-- Question blocks (phase 3 protocol)
---------------------------------------------------------------------------

--- RFC 4122 v4 UUID. Kernel source first; math.random fallback keeps the
--- command working in odd environments (both hosts are Linux).
local function uuid()
  local fd = io.open("/proc/sys/kernel/random/uuid", "r")
  if fd then
    local id = fd:read("*l")
    fd:close()
    if id and id:match("^[%x-]+$") then
      return id
    end
  end
  return (string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
    local v = c == "x" and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end))
end

local function blank(line)
  return line == nil or line:match("^%s*$") ~= nil
end

--- Insert an open question block below the current paragraph, or below the
--- selected range when invoked with one. IDs are UUID-backed and stay stable:
--- `explainctl` flips status="open" to "resolved", never rewrites the id.
local function explain_ask(cmd)
  local bufnr = vim.api.nvim_get_current_buf()

  -- Reading is exactly when questions come up: leave READ mode through
  -- readmode's own API so its saved state stays consistent, instead of
  -- failing on the nomodifiable edit guard.
  local rm = readmode()
  if rm and rm.is_read(bufnr) then
    rm.set_mode(bufnr, "edit", { silent = true })
    notify("Switched to EDIT mode for the question")
  end
  if not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
    notify("Buffer is not modifiable (submit running?)", vim.log.levels.ERROR)
    return
  end

  local last = vim.api.nvim_buf_line_count(bufnr)
  local line_at = function(l)
    return vim.api.nvim_buf_get_lines(bufnr, l - 1, l, true)[1]
  end

  -- Anchor line: end of the selection, or end of the cursor's paragraph.
  local target = cmd.range > 0 and cmd.line2 or vim.api.nvim_win_get_cursor(0)[1]
  if not blank(line_at(target)) then
    while target < last and not blank(line_at(target + 1)) do
      target = target + 1
    end
  end

  local block = {}
  if not blank(line_at(target)) then
    table.insert(block, "")
  end
  table.insert(block, ('<!-- explain-question id="q-%s" status="open" -->'):format(uuid()))
  table.insert(block, "> [!QUESTION]")
  table.insert(block, "> ")
  table.insert(block, "<!-- /explain-question -->")
  if target < last and not blank(line_at(target + 1)) then
    table.insert(block, "")
  end
  vim.api.nvim_buf_set_lines(bufnr, target, target, true, block)

  -- Land on the empty callout line, ready to type the question.
  vim.api.nvim_win_set_cursor(0, { target + #block - 1, 0 })
  vim.cmd("startinsert!")
end

---------------------------------------------------------------------------
-- Async submit (phase 4) against the explainctl JSON protocol
---------------------------------------------------------------------------

-- Per-root in-instance state: { saved = { [buf] = {modifiable=..., readonly=...} } }.
-- The in-instance flag fails fast; the authoritative guard is explainctl's
-- flock on <root>/.explain.lock (a second Neovim instance bypasses this table).
local active = {}

--- Freeze loaded explanation buffers while the external writer runs,
--- remembering the options to restore afterwards.
local function lock_buffers(root)
  local saved = {}
  for _, buf in ipairs(buffers_under(root)) do
    saved[buf] = { modifiable = vim.bo[buf].modifiable, readonly = vim.bo[buf].readonly }
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true
    -- Freeze marker: readmode refuses to change modes while this is set, so
    -- :ReadMode cannot flip 'modifiable' underneath the lock.
    vim.b[buf].explain_submit_lock = true
  end
  return saved
end

local function unlock_buffers(saved)
  for buf, opts in pairs(saved) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      vim.bo[buf].modifiable = opts.modifiable
      vim.bo[buf].readonly = opts.readonly
      vim.b[buf].explain_submit_lock = nil
    end
  end
end

--- Save every modified explanation buffer, or explain why the submit must not
--- start. A modified buffer this instance cannot write (readonly,
--- nomodifiable, or a failing write) would silently diverge from what
--- explainctl reads from disk.
---@return boolean ok
local function save_tree(root)
  for _, buf in ipairs(buffers_under(root)) do
    if vim.bo[buf].modified then
      if vim.bo[buf].readonly or not vim.bo[buf].modifiable then
        notify(("Not submitting: %s has unsaved changes that cannot be written"):format(buf_file(buf)),
          vim.log.levels.ERROR)
        return false
      end
      local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
        vim.cmd("silent update")
      end)
      if not ok then
        notify(("Not submitting: failed to write %s: %s"):format(buf_file(buf), err), vim.log.levels.ERROR)
        return false
      end
    end
  end
  return true
end

--- Return the buffers that were dropped from READ to EDIT for a submit back
--- to READ mode. Runs after unlock_buffers: the unlock restores the pre-lock
--- EDIT options, and set_mode("read") then re-saves them consistently.
local function restore_reading(reading)
  local rm = readmode()
  if not rm then
    return
  end
  for _, buf in ipairs(reading or {}) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
      rm.set_mode(buf, "read", { silent = true })
    end
  end
end

--- Apply the explainctl result protocol:
--- {status, root, submitted, updated, created, focus, resolved_question_ids}.
local function on_submit_exit(root, res)
  local state = active[root]
  active[root] = nil
  if state then
    unlock_buffers(state.saved)
    restore_reading(state.reading)
  end

  local result
  if res.stdout and res.stdout ~= "" then
    local ok, parsed = pcall(vim.json.decode, res.stdout)
    if ok and type(parsed) == "table" then
      result = parsed
    end
  end

  -- Reload from disk only after the external writer has exited. On failure
  -- explainctl restored its pre-run snapshot, so reloading is right then too.
  vim.cmd("checktime")

  -- Busy (exit 75 / EX_TEMPFAIL) is not a failure: the question block stays
  -- in the file and the user resubmits once the running update completes.
  if res.code == 75 or (result and result.status == "busy") then
    local msg = result and result.message or "An explanation update is already running."
    if result and result.active_pid then
      msg = ("%s (pid %d)"):format(msg, result.active_pid)
    end
    notify(msg, vim.log.levels.WARN)
    return
  end

  if res.code ~= 0 then
    local detail = (result and result.message) or vim.trim(res.stderr or "")
    notify(("Submit failed (exit %d)%s"):format(res.code, detail ~= "" and ": " .. detail or ""),
      vim.log.levels.ERROR)
    return
  end

  result = result or {}
  -- New children become Bufferline entries; parents stay listed because
  -- :badd/:edit never unload them (Bufferline navigation, no tabpages).
  for _, file in ipairs(result.created or {}) do
    vim.cmd("badd " .. vim.fn.fnameescape(file))
  end
  if type(result.focus) == "string" and result.focus ~= "" then
    vim.cmd("edit " .. vim.fn.fnameescape(result.focus))
  end

  local resolved = result.resolved_question_ids or {}
  if result.status and result.status ~= "updated" and #resolved == 0 then
    notify(("explainctl: %s"):format(result.message or result.status))
  else
    notify(("Updated %d, created %d, resolved %d question(s)"):format(
      #(result.updated or {}), #(result.created or {}), #resolved))
  end
end

local function explain_submit()
  local file = buf_file(vim.api.nvim_get_current_buf())
  local root = find_root(file)
  if not root then
    notify("No .explain.json above this file", vim.log.levels.ERROR)
    return
  end
  if active[root] then
    notify("A submit for this explanation is already running", vim.log.levels.WARN)
    return
  end
  -- READ-mode buffers are nomodifiable, which save_tree would refuse to
  -- write. Drop them to EDIT through readmode's API for the duration of the
  -- submit; on_submit_exit (or any early failure) puts them back to READ.
  local rm = readmode()
  local reading = {}
  if rm then
    for _, buf in ipairs(buffers_under(root)) do
      if rm.is_read(buf) then
        table.insert(reading, buf)
        rm.set_mode(buf, "edit", { silent = true })
      end
    end
  end

  if not save_tree(root) then
    restore_reading(reading)
    return
  end

  active[root] = { saved = lock_buffers(root), reading = reading }
  local ok, err = pcall(vim.system, { "explainctl", "submit", "--json", file }, { text = true }, function(res)
    vim.schedule(function()
      on_submit_exit(root, res)
    end)
  end)
  if not ok then
    unlock_buffers(active[root].saved)
    active[root] = nil
    restore_reading(reading)
    notify("Could not start explainctl: " .. err, vim.log.levels.ERROR)
    return
  end
  notify("Submitting open questions\u{2026}")
end

---------------------------------------------------------------------------
-- Status and root navigation
---------------------------------------------------------------------------

local function explain_status()
  local root = find_root(buf_file(vim.api.nvim_get_current_buf()))
  if not root then
    notify("No .explain.json above this file", vim.log.levels.ERROR)
    return
  end
  local lines = { "root: " .. root }
  table.insert(lines, "instance submit: " .. (active[root] and "running" or "idle"))
  local meta = read_metadata(root)
  if meta then
    for _, key in ipairs(vim.fn.sort(vim.tbl_keys(meta))) do
      if type(meta[key]) ~= "table" then
        table.insert(lines, ("%s: %s"):format(key, tostring(meta[key])))
      end
    end
  end
  -- explainctl writes lock-owner diagnostics (pid, start time, submitted
  -- path) into .explain.lock for exactly this display; file existence says
  -- nothing about whether the kernel lock is actually held.
  local lock = io.open(root .. "/.explain.lock", "r")
  if lock then
    local owner = vim.trim(lock:read("*a") or "")
    lock:close()
    if owner ~= "" then
      table.insert(lines, "last lock owner: " .. owner)
    end
  end
  notify(table.concat(lines, "\n"))
end

local function explain_open_root()
  local root = find_root(buf_file(vim.api.nvim_get_current_buf()))
  if not root then
    notify("No .explain.json above this file", vim.log.levels.ERROR)
    return
  end
  local meta = read_metadata(root) or {}
  local doc
  for _, key in ipairs({ "root_document", "document", "root" }) do
    local value = meta[key]
    if type(value) == "string" and value:match("%.md$") then
      doc = value
      break
    end
  end
  doc = doc or "explanation.md"
  if not doc:match("^/") then
    doc = root .. "/" .. doc
  end
  vim.cmd("edit " .. vim.fn.fnameescape(doc))
end

---------------------------------------------------------------------------
-- Initial-question entry (out-of-band Herdr launch)
---------------------------------------------------------------------------

-- The Herdr `herdr-explain-current` script opens this Neovim inside the
-- dedicated Kitty window and passes the origin Claude session out-of-band via
-- EXPLAIN_ORIGIN_SESSION_ID / EXPLAIN_ORIGIN_CWD / EXPLAIN_ORIGIN_LAUNCHER
-- (always set together). Nothing touches the original Claude transcript: the
-- question is asked here and handed straight to `explainctl new`.

local creating = false

local function on_new_exit(res)
  creating = false
  local result
  if res.stdout and res.stdout ~= "" then
    local ok, parsed = pcall(vim.json.decode, res.stdout)
    if ok and type(parsed) == "table" then
      result = parsed
    end
  end
  local focus = result and type(result.focus) == "string" and result.focus or nil
  if res.code ~= 0 or not focus then
    local detail = (result and result.message) or vim.trim(res.stderr or "")
    notify(
      ("Creating the explanation failed (exit %d)%s\n:ExplainNew retries the prompt"):format(
        res.code,
        detail ~= "" and ": " .. detail or ""
      ),
      vim.log.levels.ERROR
    )
    return
  end
  vim.cmd("edit " .. vim.fn.fnameescape(focus))
  notify("Explanation created: " .. (result.root or focus))
end

--- Prompt for the initial explanation question and create the workspace by
--- running `explainctl new` against the origin metadata from the launcher.
--- This Neovim already is the workspace, hence --no-open.
local function explain_new()
  local sid = vim.env.EXPLAIN_ORIGIN_SESSION_ID
  local cwd = vim.env.EXPLAIN_ORIGIN_CWD
  local launcher = vim.env.EXPLAIN_ORIGIN_LAUNCHER
  if not sid or sid == "" then
    notify("EXPLAIN_ORIGIN_SESSION_ID is not set; launch via herdr-explain-current", vim.log.levels.ERROR)
    return
  end
  if not cwd or cwd == "" or not launcher or launcher == "" then
    notify("Incomplete origin metadata: EXPLAIN_ORIGIN_CWD and EXPLAIN_ORIGIN_LAUNCHER must be set",
      vim.log.levels.ERROR)
    return
  end
  if creating then
    notify("An explanation is already being created", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "What needs explaining? " }, function(question)
    question = question and vim.trim(question) or ""
    if question == "" then
      notify("Cancelled; :ExplainNew retries the prompt")
      return
    end
    creating = true
    local ok, err = pcall(vim.system, {
      "explainctl",
      "new",
      "--session-id",
      sid,
      "--cwd",
      cwd,
      "--launcher",
      launcher,
      "--question",
      question,
      "--json",
      "--no-open",
    }, { text = true }, function(res)
      vim.schedule(function()
        on_new_exit(res)
      end)
    end)
    if not ok then
      creating = false
      notify("Could not start explainctl: " .. err, vim.log.levels.ERROR)
      return
    end
    notify("Creating explanation\u{2026}")
  end)
end

---------------------------------------------------------------------------
-- Per-buffer activation
---------------------------------------------------------------------------

local function attach(bufnr)
  if vim.b[bufnr].explain_attached then
    return
  end
  local root = find_root(buf_file(bufnr))
  if not root then
    return
  end
  vim.b[bufnr].explain_attached = true
  vim.b[bufnr].explain_root = root

  local cmd = vim.api.nvim_buf_create_user_command
  cmd(bufnr, "ExplainAsk", explain_ask, { range = true, desc = "Insert an anchored explanation question" })
  cmd(bufnr, "ExplainSubmit", explain_submit, { desc = "Save the tree and submit open questions" })
  cmd(bufnr, "ExplainStatus", explain_status, { desc = "Show explanation root, metadata, and lock state" })
  cmd(bufnr, "ExplainOpenRoot", explain_open_root, { desc = "Open the root explanation document" })

  local map = vim.keymap.set
  map({ "n", "x" }, "<localleader>q", ":ExplainAsk<CR>", { buffer = bufnr, silent = true, desc = "Explain: ask" })
  map("n", "<localleader>s", explain_submit, { buffer = bufnr, desc = "Explain: submit" })
end

local group = vim.api.nvim_create_augroup("explain-workspace", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = function(ev)
    attach(ev.buf)
  end,
})

-- Global: also the retry path when the startup prompt was cancelled or failed.
vim.api.nvim_create_user_command("ExplainNew", explain_new, { desc = "Create an explanation from the origin session" })

-- Launched by herdr-explain-current: ask for the initial question once the UI
-- is up (snacks.nvim loads eagerly, so Snacks.input backs vim.ui.input here).
if vim.env.EXPLAIN_ORIGIN_SESSION_ID and vim.env.EXPLAIN_ORIGIN_SESSION_ID ~= "" then
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    once = true,
    callback = function()
      vim.schedule(explain_new)
    end,
  })
end

return {}
