return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        r_language_server = {
          mason = false,
          -- We wrap the command with "env" to inject the variable reliably
          cmd = {
            "env",
            "R_PROFILE_USER=" .. os.getenv("HOME") .. "/.Rprofile",
            "R",
            "--slave",
            "-e",
            "languageserver::run()",
          },
        },
      },
    },
  },
}
