-- Smooth animated page scrolling.
--
-- Two interchangeable backends are implemented here. Only ONE should be
-- active at a time -- flip SCROLL_BACKEND below to switch.
--
--   "snacks"    (ACTIVE by default) -- uses folke/snacks.nvim's `scroll`
--               module, configured in ../plugins/snacks.lua (search for
--               `scroll = {` around line 41 there). snacks.nvim is already a
--               required dependency, so this is the lower-footprint option:
--               it hooks generically into any WinScrolled event with a
--               topline change (see ~/.local/share/nvim/lazy/snacks.nvim/
--               lua/snacks/scroll.lua:217-227), so it transparently animates
--               <C-f>/<C-b>/<C-d>/<C-u>, zz/zt/zb, gg/G, search jumps, etc.
--               without needing explicit keymaps.
--
--   "neoscroll" (INERT by default) -- uses karb94/neoscroll.nvim, which
--               instead maps a fixed set of keys to its own scroll
--               functions. Configured below.
--
-- IMPORTANT: this flag only controls the neoscroll.nvim spec's `enabled`
-- field below. It CANNOT reach into ../plugins/snacks.lua and flip its
-- `scroll.enabled` value for you (lazy.nvim specs don't share mutable
-- state that way). If you switch this flag to "neoscroll", you MUST also
-- open ../plugins/snacks.lua and set `scroll.enabled = false` there --
-- otherwise both plugins will try to animate the same scroll events and
-- fight each other. A comment pointing back here is left at that call site.
local SCROLL_BACKEND = "snacks" -- "snacks" | "neoscroll"

return {
  {
    "karb94/neoscroll.nvim",
    -- Only load/enable when this backend is selected. `enabled = false`
    -- makes lazy.nvim skip the plugin entirely (no install, no setup call).
    enabled = SCROLL_BACKEND == "neoscroll",
    event = { "BufReadPost", "BufNewFile" },
    ---@module "neoscroll"
    opts = {
      -- Default easing used by any call below that doesn't override it.
      -- neoscroll README "Easing functions" section and
      -- lua/neoscroll/init.lua:3-14 (config.default_options.easing) confirm
      -- the valid names: linear, quadratic, cubic, quartic, quintic,
      -- circular, sine.
      easing = "sine",
      hide_cursor = true, -- default_options.hide_cursor, init.lua:5
      stop_eof = true, -- default_options.stop_eof, init.lua:6
      respect_scrolloff = false, -- default_options.respect_scrolloff, init.lua:7
      cursor_scrolls_alone = true, -- default_options.cursor_scrolls_alone, init.lua:8
      performance_mode = false, -- default_options.performance_mode, init.lua:10
      -- We build our own explicit key -> function mappings below instead of
      -- using the `mappings` list (which only wires up the plugin's
      -- hardcoded 250/450ms durations, see init.lua:424-435). Passing an
      -- empty list here disables neoscroll's own keymap.set calls so ours
      -- (set in `keys`) are the only ones in effect.
      mappings = {},
    },
    -- Explicit per-key mappings with tuned durations/easing, following the
    -- "Custom mappings" recipe in the neoscroll README (karb94/neoscroll.nvim
    -- README.md:88-107, "Easing functions" examples README.md:134-148).
    -- <C-f>/<C-b> (whole page) get sine easing at 150-250ms scaled by
    -- distance via ctrl_f/ctrl_b's own duration param (init.lua:225-235,
    -- ctrl_b/ctrl_f just call scroll(+-winheight, opts)).
    keys = function()
      if SCROLL_BACKEND ~= "neoscroll" then
        return {}
      end
      -- Each callback requires("neoscroll") lazily at call time rather than
      -- at the top of this function: lazy.nvim evaluates `keys` functions
      -- during spec resolution, before the plugin is added to the
      -- runtimepath, so a top-level require here would error even when this
      -- backend is selected.
      return {
        {
          "<C-u>",
          function()
            require("neoscroll").ctrl_u({ duration = 180, easing = "sine" })
          end,
          mode = { "n", "x" },
          desc = "Scroll half page up",
        },
        {
          "<C-d>",
          function()
            require("neoscroll").ctrl_d({ duration = 180, easing = "sine" })
          end,
          mode = { "n", "x" },
          desc = "Scroll half page down",
        },
        {
          "<C-b>",
          function()
            require("neoscroll").ctrl_b({ duration = 250, easing = "sine" })
          end,
          mode = { "n", "x" },
          desc = "Scroll page up",
        },
        {
          "<C-f>",
          function()
            require("neoscroll").ctrl_f({ duration = 200, easing = "sine" })
          end,
          mode = { "n", "x" },
          desc = "Scroll page down",
        },
        {
          "<C-y>",
          function()
            require("neoscroll").scroll(-0.1, { move_cursor = false, duration = 100, easing = "quadratic" })
          end,
          mode = { "n", "x" },
          desc = "Scroll up one line",
        },
        {
          "<C-e>",
          function()
            require("neoscroll").scroll(0.1, { move_cursor = false, duration = 100, easing = "quadratic" })
          end,
          mode = { "n", "x" },
          desc = "Scroll down one line",
        },
        {
          "zt",
          function()
            require("neoscroll").zt({ half_win_duration = 200, easing = "sine" })
          end,
          mode = { "n", "x" },
          desc = "Scroll cursor to top",
        },
        {
          "zz",
          function()
            require("neoscroll").zz({ half_win_duration = 200, easing = "sine" })
          end,
          mode = { "n", "x" },
          desc = "Scroll cursor to center",
        },
        {
          "zb",
          function()
            require("neoscroll").zb({ half_win_duration = 200, easing = "sine" })
          end,
          mode = { "n", "x" },
          desc = "Scroll cursor to bottom",
        },
      }
    end,
  },
}
