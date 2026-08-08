return {
  {
    "OXY2DEV/markview.nvim",
    event = {
      {
        event = { "BufReadPre", "BufNewFile" },
        pattern = { "*.md", "*.markdown", "*.quarto", "*.rmd" },
      },
    },
    opts = {
      preview = {
        -- Show raw markdown under the cursor while in insert mode; keep the
        -- rest of the buffer (and normal/command mode) fully rendered.
        modes = { "n", "no", "c", "i" },
        hybrid_modes = { "i" },
        icon_provider = "mini",
      },
    },
    config = function(_, opts)
      require("markview").setup(opts)
    end,
  },
}
