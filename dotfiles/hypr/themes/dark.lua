-- Dark (phosphor) mode. Included by hyprland.lua through the
-- ~/.local/state/hypr/current-theme.lua symlink, which switch-dark/switch-light
-- repoint. See home/desktop/theming.nix.

hl.config({
  general = {
    gaps_in = 8,
    gaps_out = 12,
    border_size = 1,
    col = {
      active_border = "rgba(48504Bff)",
      inactive_border = "rgba(282E2Aff)",
    },
  },

  misc = {
    background_color = "0x050806",
  },

  decoration = {
    rounding = 12,
    -- screen-shader owns the live shader setting so cold starts, monitor IDs,
    -- theme mode, and the manual preference all follow one policy.

    -- Change transparency of focused and unfocused windows
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

hl.on("hyprland.start", function()
  -- Brown-black CRT glass background for startup.
  hl.exec_cmd("pkill swaybg || true; setsid -f swaybg -c 050806")
  hl.exec_cmd("hyprctl setcursor Bibata-Original-VT220 22")
end)
