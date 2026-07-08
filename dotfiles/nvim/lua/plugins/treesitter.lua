return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      ensure_installed = {
        "bash",
        "dot",
        "gitcommit",
        "groovy",
        "json",
        "jsonc",
        "lua",
        "luadoc",
        "markdown",
        "markdown_inline",
        "nix",
        "r",
        "rnoweb",
        "toml",
        "typst",
        "vim",
        "vimdoc",
        "yaml",
      },
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
      vim.treesitter.language.register("groovy", "nextflow")
    end,
  },
}
