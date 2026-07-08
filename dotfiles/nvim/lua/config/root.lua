local M = {}

local markers = {
  ".git",
  "flake.nix",
  "typst.toml",
  "DESCRIPTION",
  "package.json",
  ".here",
}

function M.get(buf)
  return vim.fs.root(buf or 0, markers) or vim.uv.cwd()
end

return M
