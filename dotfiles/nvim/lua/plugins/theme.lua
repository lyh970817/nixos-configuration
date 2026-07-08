return {
  {
    "f-person/auto-dark-mode.nvim",
    event = "UIEnter",
    opts = {
      update_interval = 1000,
      set_dark_mode = function()
        require("config.theme").apply("dark")
      end,
      set_light_mode = function()
        require("config.theme").apply("light")
      end,
    },
    config = function(_, opts)
      local auto_dark_mode = require("auto-dark-mode")
      auto_dark_mode.setup(opts)
      auto_dark_mode.init()
    end,
  },
}
