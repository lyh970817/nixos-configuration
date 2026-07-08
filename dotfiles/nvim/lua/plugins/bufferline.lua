return {
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-mini/mini.icons", "folke/snacks.nvim" },
    keys = {
      { "<leader>bp", "<cmd>BufferLineTogglePin<cr>", desc = "Toggle Pin" },
      { "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", desc = "Delete Non-Pinned Buffers" },
      { "<leader>br", "<cmd>BufferLineCloseRight<cr>", desc = "Delete Buffers to the Right" },
      { "<leader>bl", "<cmd>BufferLineCloseLeft<cr>", desc = "Delete Buffers to the Left" },
      { "<S-h>", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev Buffer" },
      { "<S-l>", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
      { "[b", "<cmd>BufferLineCyclePrev<cr>", desc = "Prev Buffer" },
      { "]b", "<cmd>BufferLineCycleNext<cr>", desc = "Next Buffer" },
      { "[B", "<cmd>BufferLineMovePrev<cr>", desc = "Move Buffer Prev" },
      { "]B", "<cmd>BufferLineMoveNext<cr>", desc = "Move Buffer Next" },
      { "<leader>bj", "<cmd>BufferLinePick<cr>", desc = "Pick Buffer" },
    },
    opts = {
      options = {
        close_command = function(n)
          require("snacks").bufdelete(n)
        end,
        right_mouse_command = function(n)
          require("snacks").bufdelete(n)
        end,
        diagnostics = "nvim_lsp",
        always_show_bufferline = false,
        diagnostics_indicator = function(_, _, diag)
          local icons = require("config.icons").diagnostics
          local errors = diag.error and icons.Error .. diag.error .. " " or ""
          local warnings = diag.warning and icons.Warn .. diag.warning or ""
          return vim.trim(errors .. warnings)
        end,
        offsets = {
          { filetype = "snacks_layout_box" },
        },
        get_element_icon = function(opts)
          local ok, mini_icons = pcall(require, "mini.icons")
          if ok then
            return mini_icons.get("filetype", opts.filetype)
          end
        end,
      },
    },
  },
}
