return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        r_language_server = {
          mason = false,
          cmd = {
            "env",
            "R_PROFILE_USER=/dev/null",
            "R",
            "--no-echo",
            "--no-restore",
            "-e",
            "languageserver::run()",
          },
          filetypes = { "r", "rmd", "quarto" },
          root_dir = function(bufnr, on_dir)
            local markers = {
              "renv.lock",
              ".Rprofile",
              "DESCRIPTION",
              "NAMESPACE",
              ".Rbuildignore",
              ".here",
              ".git",
            }
            local root = vim.fs.root(bufnr, markers)
            local path = vim.api.nvim_buf_get_name(bufnr)
            on_dir(root or (path ~= "" and vim.fs.dirname(path)) or vim.uv.cwd())
          end,
        },
      },
    },
  },
}
