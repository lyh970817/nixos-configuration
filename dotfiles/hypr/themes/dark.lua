-- Dark (phosphor) mode. Included by hyprland.lua through the
-- ~/.local/state/hypr/current-theme.lua symlink, which switch-dark/switch-light
-- repoint. See home/desktop/theming.nix.

local onHyprlandStart = ...

_G.quiet_graphite_dark = true

-- Super+Enter's floating terminal, lifted just off the phosphor background so
-- the wallpaper reads through it. Tune here; 1 turns it off. Kept high because
-- the rule dims the glyphs along with the background.
_G.float_terminal_opacity = 0.9

-- How far an unfocused window is dimmed, spent by the window rules in
-- hyprland.lua rather than by decoration:inactive_opacity below, so that only
-- tiled foot and Brave windows dim and dialogs, file pickers and image
-- previews stay opaque. 1 turns it off.
_G.inactive_opacity = 0.93

hl.config({
  general = {
    gaps_in = 8,
    gaps_out = 12,
    border_size = 1,
    col = {
      active_border = "rgba(3D8E48ff)",
      inactive_border = "rgba(15261Aff)",
    },
  },

  misc = {
    background_color = "0x050806",
  },

  decoration = {
    rounding = 4,
    -- screen-shader owns the live shader setting so cold starts, monitor IDs,
    -- theme mode, and the manual preference all follow one policy.

    -- Both pinned to 1: the mode's dimming is applied per window rule, from
    -- _G.inactive_opacity above.
    inactive_opacity = 1,
    active_opacity = 1,

    shadow = {
      enabled = true,
      range = 35,
      render_power = 2,
      sharp = false,
      color = "rgba(00000075)",
      color_inactive = "rgba(00000047)",
      offset = { 0, 10 },
    },

    blur = {
      enabled = false,
      size = 3,
      passes = 1,

      vibrancy = 0.1696,
    },
  },
})

-- Startup cursor, so a dark-mode login matches switch-dark without waiting for
-- it. No hyprcursor variant of this theme is built, and no hyprcursor theme is
-- installed on this machine at all (nothing on the icon path ships a
-- manifest.hl), so HYPRCURSOR_THEME never resolves and Hyprland always takes
-- the XCursor path -- exactly what Adwaita did here before. Verified, not
-- assumed: CCursorManager::changeTheme only reaches
-- CXCursorManager::syncGsettings on the XCursor fallback branch, and a
-- `hyprctl setcursor <theme> <size>` does write that size straight back into
-- gsettings.
--
-- These three are only read when a client starts, so they govern client-drawn
-- cursors (foot, Chromium/Electron, anything on libwayland-cursor) rather than
-- the compositor's own pointer, which follows `hyprctl setcursor` below. A
-- client that was already running keeps whatever it started with; switch-dark /
-- switch-light push these into Hyprland's environment so at least newly spawned
-- clients follow the mode.
hl.env("HYPRCURSOR_THEME", "Bibata-Original-VT220")
hl.env("XCURSOR_THEME", "Bibata-Original-VT220")
hl.env("XCURSOR_SIZE", "22")

onHyprlandStart(function()
  -- Rock-art frieze on the brown-black CRT glass background, for startup.
  -- Centred at native size; see darkWallpaper in home/desktop/theming.nix.
  hl.exec_cmd(
    "pkill swaybg || true; setsid -f swaybg -i "
      .. os.getenv("HOME")
      .. "/.local/share/wallpapers/Petroglyph_frieze.png -m center -c 050806"
  )
  hl.exec_cmd("hyprctl setcursor Bibata-Original-VT220 22")
end)
