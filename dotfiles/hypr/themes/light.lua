-- Light (e-ink) mode. Included by hyprland.lua through the
-- ~/.local/state/hypr/current-theme.lua symlink, which switch-dark/switch-light
-- repoint. See home/desktop/theming.nix.

local onHyprlandStart = ...

_G.quiet_graphite_dark = false

-- The floating terminal stays opaque here. This mode is pure black on white on
-- an e-ink panel, and blending either one toward the other is the grey the
-- palette exists to avoid -- see the dark twin for the knob.
_G.float_terminal_opacity = 1

-- How far an unfocused window is dimmed, spent by the window rules in
-- hyprland.lua rather than by decoration:inactive_opacity below, so that only
-- tiled kitty and Brave windows dim and dialogs, file pickers and image
-- previews stay opaque. 1 turns it off.
_G.inactive_opacity = 0.7

hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 15,
    border_size = 2,
    col = {
      active_border = "rgba(000000ff)",
      inactive_border = "rgba(00000000)",
    },
  },

  misc = {
    background_color = "0xffffff",
  },

  decoration = {
    rounding = 4,
    rounding_power = 2,

    -- Both pinned to 1: the mode's dimming is applied per window rule, from
    -- _G.inactive_opacity above.
    inactive_opacity = 1,
    active_opacity = 1,

    shadow = {
      enabled = false,
      range = 4,
      render_power = 3,
      color = "rgba(1a1a1aee)",
    },

    blur = {
      enabled = false,
      size = 3,
      passes = 1,

      vibrancy = 0.1696,
    },
  },
})

hl.env("HYPRCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")

onHyprlandStart(function()
  hl.exec_cmd("hyprctl setcursor Adwaita 24")
  -- Wallpaper for startup
  hl.exec_cmd(
    "pkill swaybg || true; setsid -f swaybg -i "
      .. os.getenv("HOME")
      .. "/.local/share/wallpapers/Taiji_mandala.png -m fit -c ffffff"
  )
end)
