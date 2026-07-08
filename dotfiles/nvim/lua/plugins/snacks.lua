return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bigfile = { enabled = true },
      bufdelete = { enabled = true },
      explorer = {
        enabled = true,
        replace_netrw = true,
        trash = false,
      },
      input = { enabled = true },
      notifier = { enabled = true },
      picker = {
        enabled = true,
        sources = {
          explorer = {
            win = {
              list = {
                keys = {
                  ["a"] = false,
                  ["d"] = false,
                  ["r"] = false,
                  ["c"] = false,
                  ["m"] = false,
                  ["p"] = false,
                  ["<c-t>"] = false,
                },
              },
            },
          },
        },
      },
      quickfile = { enabled = true },
      scope = { enabled = true },
      scroll = { enabled = false },
      words = { enabled = true },
      zen = { enabled = true },
    },
    keys = {
      {
        "<leader><space>",
        function()
          require("snacks").picker.files({ cwd = require("config.root").get(0) })
        end,
        desc = "Find Files",
      },
      { "<leader>,", function() require("snacks").picker.buffers() end, desc = "Buffers" },
      {
        "<leader>/",
        function()
          require("snacks").picker.grep({ cwd = require("config.root").get(0) })
        end,
        desc = "Grep",
      },
      { "<leader>:", function() require("snacks").picker.command_history() end, desc = "Command History" },
      {
        "<leader>e",
        function()
          require("snacks").explorer({ cwd = require("config.root").get(0) })
        end,
        desc = "Explorer",
      },
      { "<leader>E", function() require("snacks").explorer() end, desc = "Explorer (cwd)" },
      { "<leader>fb", function() require("snacks").picker.buffers() end, desc = "Buffers" },
      {
        "<leader>ff",
        function()
          require("snacks").picker.files({ cwd = require("config.root").get(0) })
        end,
        desc = "Find Files",
      },
      { "<leader>fF", function() require("snacks").picker.files() end, desc = "Find Files (cwd)" },
      { "<leader>fr", function() require("snacks").picker.recent() end, desc = "Recent" },
      { "<leader>sb", function() require("snacks").picker.lines() end, desc = "Buffer Lines" },
      { "<leader>sB", function() require("snacks").picker.grep_buffers() end, desc = "Grep Open Buffers" },
      {
        "<leader>sg",
        function()
          require("snacks").picker.grep({ cwd = require("config.root").get(0) })
        end,
        desc = "Grep",
      },
      { "<leader>sG", function() require("snacks").picker.grep() end, desc = "Grep (cwd)" },
      {
        "<leader>sw",
        function()
          require("snacks").picker.grep_word({ cwd = require("config.root").get(0) })
        end,
        desc = "Word or Selection",
        mode = { "n", "x" },
      },
      { "<leader>s/", function() require("snacks").picker.search_history() end, desc = "Search History" },
      { "<leader>sR", function() require("snacks").picker.resume() end, desc = "Resume Picker" },
      { "<leader>wm", function() require("snacks").toggle.zoom():toggle() end, desc = "Maximize Window" },
      { "<leader>uZ", function() require("snacks").toggle.zoom():toggle() end, desc = "Maximize Window" },
      { "<leader>uz", function() require("snacks").zen() end, desc = "Zen Mode" },
      {
        "<leader>us",
        function()
          require("snacks").toggle.option("spell", { name = "Spelling" }):toggle()
        end,
        desc = "Toggle Spelling",
      },
      {
        "<leader>uw",
        function()
          require("snacks").toggle.option("wrap", { name = "Wrap" }):toggle()
        end,
        desc = "Toggle Wrap",
      },
      {
        "<leader>ud",
        function()
          require("snacks").toggle.diagnostics():toggle()
        end,
        desc = "Toggle Diagnostics",
      },
      {
        "<leader>ul",
        function()
          require("snacks").toggle.line_number():toggle()
        end,
        desc = "Toggle Line Numbers",
      },
      {
        "<leader>uL",
        function()
          require("snacks").toggle.option("relativenumber", { name = "Relative Number" }):toggle()
        end,
        desc = "Toggle Relative Numbers",
      },
      {
        "<leader>uc",
        function()
          require("snacks").toggle.option("conceallevel", { off = 0, on = 2, name = "Conceal Level" }):toggle()
        end,
        desc = "Toggle Conceal",
      },
      {
        "<leader>ub",
        function()
          require("snacks").toggle.option("background", {
            off = "light",
            on = "dark",
            name = "Dark Background",
          }):toggle()
        end,
        desc = "Toggle Background",
      },
    },
    config = function(_, opts)
      require("snacks").setup(opts)
    end,
  },
}
