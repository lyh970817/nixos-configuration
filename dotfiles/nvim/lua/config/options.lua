-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Disable the highlight of the line where the cursor is
vim.opt.cursorline = false

-- Remove the tilde (~) characters from empty lines at the end of buffer
vim.opt.fillchars = { eob = " " }

-- Sync with system clipboard
vim.opt.clipboard = "unnamedplus"

vim.opt.equalalways = false

-- 1. Helper function to check system theme via gsettings
local function get_system_theme()
  -- Run the command and get output
  local handle = io.popen("gsettings get org.gnome.desktop.interface color-scheme")
  if not handle then
    return "prefer-dark"
  end -- Fallback if command fails

  local result = handle:read("*a")
  handle:close()

  -- Clean up the output (remove quotes, newlines, whitespace)
  result = result:gsub("['\"\n\r]", "")
  return result
end

-- 2. Determine mode and apply IMMEDIATELY
local mode = get_system_theme()

if mode == "prefer-light" then
  vim.opt.background = "light"
  -- Use pcall to prevent errors if the local file is missing during a fresh install
  pcall(vim.cmd, "colorscheme bow-wob")
else
  -- Default to dark for safety
  vim.opt.background = "dark"
  pcall(vim.cmd, "colorscheme matrix")
end

vim.api.nvim_create_autocmd("VimResized", {
  pattern = "*",
  command = "redraw!",
  desc = "Force redraw on resize to prevent text loss",
})

vim.filetype.add({
  extension = {
    nf = "nextflow",
  },
})
