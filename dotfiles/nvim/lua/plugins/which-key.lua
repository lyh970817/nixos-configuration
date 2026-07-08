return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      preset = "helix",
      spec = {
        { "<leader><tab>", group = "tabs" },
        { "<leader>b", group = "buffers" },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find/files" },
        { "<leader>g", group = "git" },
        { "<leader>s", group = "search/symbols" },
        { "<leader>t", group = "typst" },
        { "<leader>u", group = "ui/toggles" },
        { "<leader>w", group = "windows" },
        { "<leader>x", group = "quickfix" },
      },
    },
  },
}
