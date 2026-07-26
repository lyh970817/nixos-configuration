return {
  {
    "f-person/auto-dark-mode.nvim",
    -- When THEME_MODE is set (ssh/mosh session or shell default), the
    -- session mode is authoritative and frozen for the process's life.
    -- This poller would otherwise re-read gsettings every second and fight
    -- it, overwriting the session's mode with the machine-global one.
    enabled = vim.env.THEME_MODE == nil or vim.env.THEME_MODE == "",
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
