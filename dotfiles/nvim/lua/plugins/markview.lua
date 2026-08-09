return {
  {
    "OXY2DEV/markview.nvim",
    -- Upstream ships its own lazy loading (plugin/markview.lua is a two-line
    -- autocmd; the heavy modules load on attach) and asks not to add another
    -- layer. Any hand-written trigger list here is a second copy of the
    -- plugin's preview.filetypes that drifts out of sync -- the glob form
    -- missed .qmd and .Rmd entirely.
    lazy = false,
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
