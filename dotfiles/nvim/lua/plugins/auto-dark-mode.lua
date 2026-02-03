return {
  {
    "f-person/auto-dark-mode.nvim",
    event = "UIEnter",
    opts = {
      update_interval = 1000,
      set_dark_mode = function()
        vim.api.nvim_set_option("background", "dark")
        -- pcall ensures neovim doesn't crash if the file is missing
        local ok, _ = pcall(vim.cmd, "colorscheme matrix")
        if not ok then
          vim.notify("Colorscheme 'matrix' not found!", vim.log.levels.WARN)
        end
      end,
      set_light_mode = function()
        vim.api.nvim_set_option("background", "light")
        local ok, _ = pcall(vim.cmd, "colorscheme bow-wob")
        if not ok then
          vim.notify("Colorscheme 'bow-wob' not found!", vim.log.levels.WARN)
        end
      end,
    },
    config = function(_, opts)
      local auto_dark_mode = require("auto-dark-mode")
      auto_dark_mode.setup(opts)
      auto_dark_mode.init()
    end,
  },
}
