return {
  {
    "L3MON4D3/LuaSnip",
    opts = {
      enable_autosnippets = true,
      cut_selection_keys = "<Tab>",
    },
  },
  {
    "chomosuke/typst-preview.nvim",
    ft = "typst",
    version = "1.*",
    opts = {
      dependencies_bin = {
        tinymist = "tinymist",
        websocat = "websocat",
      },
    },
  },
  {
    "arne314/typstar",
    ft = { "typst" },
    dependencies = {
      "L3MON4D3/LuaSnip",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      {
        "<M-t>",
        "<Cmd>TypstarToggleSnippets<CR>",
        mode = { "n", "i" },
        desc = "Toggle Typstar snippets",
      },
      {
        "<M-j>",
        "<Cmd>TypstarSmartJump<CR>",
        mode = { "s", "i" },
        desc = "Typstar next snippet stop",
      },
      {
        "<M-k>",
        "<Cmd>TypstarSmartJumpBack<CR>",
        mode = { "s", "i" },
        desc = "Typstar previous snippet stop",
      },
    },
    opts = {
      add_undo_breakpoints = true,
    },
  },
}
