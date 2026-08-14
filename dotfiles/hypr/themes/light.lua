-- Light (e-ink) mode. Included by hyprland.lua through the
-- ~/.local/state/hypr/current-theme.lua symlink, which switch-dark/switch-light
-- repoint. See home/desktop/theming.nix.

local onHyprlandStart = ...

_G.quiet_graphite_dark = false

-- The floating terminal stays opaque here. This mode is pure black on white on
-- an e-ink panel, and blending either one toward the other is the grey the
-- palette exists to avoid -- see the dark twin for the knob.
_G.float_terminal_opacity = 1

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

    -- Change transparency of focused and unfocused windows
    inactive_opacity = 0.7,
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
