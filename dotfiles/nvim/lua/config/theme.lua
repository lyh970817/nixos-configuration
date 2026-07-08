local M = {}

local function read_system_scheme()
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
    pcall(vim.cmd.colorscheme, "matrix")
  end
end

function M.apply_system()
  M.apply(read_system_scheme())
end

return M
