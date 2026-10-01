-- R.nvim: a live R console in a Neovim split, with line/selection/chunk
-- sending from r, rmd and quarto buffers. The R language server stays in
-- lsp.lua; this plugin is only the REPL side.
--
-- Loaded only where an R binary is on PATH, i.e. the home role
-- (home/packages/development.nix); the laptop has no R toolchain and skips
-- it. On the first R start the plugin builds its bundled `nvimcom` R package
-- and `rnvimserver` binary into R's user library (~/R/...), which needs the
-- gcc the home role already carries; it rebuilds them itself after plugin
-- updates.
return {
  {
    "R-nvim/R.nvim",
    cond = function()
      return vim.fn.executable("R") == 1
    end,
    -- The plugin registers its filetype hooks at load time, so it is loaded
    -- eagerly (lazy.lua sets defaults.lazy = true).
    lazy = false,
    version = "~1.0",
    opts = {
      R_args = { "--quiet", "--no-save" },
      pdfviewer = "sioyek",
      hook = {
        on_filetype = function()
          -- <Enter> sends the current line (normal) or selection (visual)
          -- to R; the <LocalLeader> commands stay at their defaults
          -- (\rf start R, \rq quit, \d line, \ss selection, \aa file).
          vim.api.nvim_buf_set_keymap(0, "n", "<Enter>", "<Plug>RDSendLine", {})
          vim.api.nvim_buf_set_keymap(0, "v", "<Enter>", "<Plug>RSendSelection", {})
        end,
      },
    },
    config = function(_, opts)
      require("r").setup(opts)
    end,
  },
}
