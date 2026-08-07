local M = {}

local function read_system_scheme()
  -- THEME_MODE is the per-session theme: set by `theme-hold` for ssh/mosh
  -- sessions, and defaulted from the local monitor by the shell otherwise.
  -- When present it takes precedence over the machine-global gsettings value.
  local theme_mode = vim.env.THEME_MODE
  if theme_mode ~= nil and theme_mode ~= "" then
    return theme_mode
  end

  local handle = io.popen("gsettings get org.gnome.desktop.interface color-scheme")
  if not handle then
    return "prefer-dark"
  end

  local result = handle:read("*a")
  handle:close()

  return result:gsub("['\"\n\r]", ""):match("^%s*(.-)%s*$")
end

function M.apply(mode)
  if mode == "prefer-light" or mode == "light" then
    vim.opt.background = "light"
    pcall(vim.cmd.colorscheme, "bow-wob")
  else
    vim.opt.background = "dark"
    pcall(vim.cmd.colorscheme, "vt220-amber")
  end
end

function M.apply_system()
  M.apply(read_system_scheme())
end

return M
