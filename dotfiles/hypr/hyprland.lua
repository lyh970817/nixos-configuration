-- Hyprland configuration, Lua format.
--
-- The .conf format is deprecated and support for it is removed in Hyprland
-- 0.57. This file is the entire configuration: the Lua API has no
-- `source`/`keyword` helper, so nothing can be split out into an included
-- fragment. See share/hypr/hyprland.lua and share/hypr/stubs/hl.meta.lua in the
-- hyprland package for the reference config and the typed API stub.
--
-- Validate any edit before it goes live -- ~/.config/hypr is an out-of-store
-- symlink, so an edit here reaches the compositor with no rebuild:
--   Hyprland --verify-config --config ~/.config/hypr/hyprland.lua

local home = os.getenv("HOME")
local backends = "," .. (os.getenv("WLR_BACKENDS") or "") .. ","
local headlessOnly = os.getenv("AQ_HEADLESS_ONLY") == "1" or backends:find(",headless,", 1, true) ~= nil

-- Nested compositors are for config inspection only. Registering startup hooks
-- there would let commands such as `fcitx5 --replace`, `pkill swaybg`, and
-- systemd environment imports alter the live desktop outside the nested
-- compositor.
local function onHyprlandStart(callback)
  if not headlessOnly then
    hl.on("hyprland.start", callback)
  end
end

-- Theme fragments set this before the window rules are declared. Defaulting
-- here keeps a missing or broken fragment from leaking dark-only rules across
-- a reload.
_G.quiet_graphite_dark = false

-- Opacity of the keybind-spawned floating terminal, owned by the theme
-- fragment next to the mode's own active_opacity/inactive_opacity. 1 means
-- opaque, and is the safe default for the same reason as above.
_G.float_terminal_opacity = 1

-- How far an unfocused window is dimmed. This is deliberately NOT
-- decoration:inactive_opacity -- the themes pin that to 1 -- because a global
-- setting dims every window there is, including the dialogs, file pickers and
-- image previews that must stay readable. Only the rules below spend it, and
-- only on tiled windows. 1 means no dimming anywhere, the safe default again.
_G.inactive_opacity = 1

-- Lua's `dofile` throws when the file is missing. The theme link is created by
-- systemd-tmpfiles and the generated fragments by Home Manager, so all three
-- normally exist -- but a missing include must not take the whole config down
-- with it, because a config that raises before any bind is registered drops
-- Hyprland into emergency mode with only SUPER+Q bound.
local function include(path)
  local chunk, err = loadfile(path)
  if not chunk then
    print("[hyprland.lua] skipping " .. path .. ": " .. tostring(err))
    return
  end
  local ok, ferr = pcall(chunk, onHyprlandStart)
  if not ok then
    print("[hyprland.lua] error in " .. path .. ": " .. tostring(ferr))
  end
end

-- Mode-specific gaps, borders, and decoration are owned by the theme. Keeping
-- them out of later global blocks lets a config reload apply a mode change and
-- its window-rule state together.
include(home .. "/.local/state/hypr/current-theme.lua")
-- hyprwinwrap plugin and window rules for the dark-mode terminal wallpaper.
include(home .. "/.config/hypr/wallpaper.lua")

------------------
---- MONITORS ----
------------------

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.monitor({
  output = "desc:DSC Paperlike H D",
  mode = "2200x1650@40",
  position = "0x0",
  scale = 1.666667,
})

---------------------
---- MY PROGRAMS ----
---------------------

local terminal = "kitty"
local fileManager = "thunar"
local fileManagerCli = "kitty $SHELL -l -c yazi"
local menu = "rofi -show drun -location 2"
local windowSelect = "rofi -show window -location 2"

-------------------
---- AUTOSTART ----
-------------------

-- `hyprland.start` fires once per compositor start and not on reload, which is
-- exactly what `exec-once` meant.
onHyprlandStart(function()
  hl.exec_cmd("nm-applet &")
  hl.exec_cmd("mako &")
  hl.exec_cmd("fcitx5 -d --replace")
  hl.exec_cmd(home .. "/.config/hypr/scripts/monitor-switch.sh")
  hl.exec_cmd(
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XMODIFIERS && systemctl --user start hyprland-session.target"
  )
  hl.exec_cmd("systemctl --user start hyprwhspr.service")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- XCURSOR_THEME / XCURSOR_SIZE / HYPRCURSOR_THEME are deliberately NOT set
-- here. They belong to the mode themes, and this file includes the theme near
-- the top, so anything set here would silently win over it -- which is what a
-- stray `XCURSOR_SIZE = 24` did, pinning every client-drawn cursor to 24 while
-- the compositor drew dark mode's 22.

-- pam_env (linux-pam >= 1.7.1) drops values starting with a bare "@" from
-- /etc/pam/environment, so sessionVariables' XMODIFIERS never reaches the
-- session. Restore it here so Hyprland-spawned XWayland clients attach fcitx5.
hl.env("XMODIFIERS", "@im=fcitx")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
  general = {
    -- Set to true to enable resizing windows by clicking and dragging on
    -- borders and gaps
    resize_on_border = false,

    allow_tearing = false,

    layout = "dwindle",
  },

  cursor = {
    inactive_timeout = 0.1,
    hide_on_key_press = true,
  },

  animations = {
    enabled = false,
  },

  -- pseudotile master switch was removed in Hyprland 0.56; the mainMod + P
  -- pseudo dispatcher and per-window pseudo rules work without it now.
  dwindle = {
    preserve_split = true,
  },

  master = {
    new_status = "master",
  },

  misc = {
    force_default_wallpaper = 1, -- Set to 0 or 1 to disable the anime mascot wallpapers
    disable_hyprland_logo = true, -- If true disables the random hyprland logo / anime girl background. :(
  },

  input = {
    kb_layout = "us",

    follow_mouse = 3,
    float_switch_override_focus = 0,

    sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

    touchpad = {
      natural_scroll = true,
    },
  },
})

-- Curves and animations are still declared even though animations.enabled is
-- false, so flipping that switch at runtime gives the same result as before.
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

---------------
---- INPUT ----
---------------

hl.device({
  name = "epic-mouse-v1",
  sensitivity = -0.5,
})

-- Deliberately global: touchpad-toggle.sh reads and updates this through the
-- running Lua config's REPL. A reload creates a fresh Lua state and restores
-- both this value and the device setting to the enabled default together, so
-- the next toggle cannot act on stale state left over from before the reload.
touchpad_enabled = true
hl.device({
  name = "363030314b424e44:00-06cb:cddb-touchpad",
  enabled = touchpad_enabled,
})

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

local scripts = home .. "/.config/hypr/scripts"
local protect = scripts .. "/protected-dispatch.sh "

-- Per-role terminal/connect binds (Super+Enter, Super+Shift+Enter) and boot
-- terminal. Generated by Home Manager based on portable.role; see
-- home/programs/dotfiles.nix.
include(home .. "/.config/hypr/role.lua")

-- Manual theme toggle (both roles)
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("theme-toggle"))
-- Toggle the shared scheduled 3500 K hyprsunset setting; second press uses identity/off (Super+N).
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("hyprsunset-night"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("btop-workspace exec brave"))
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(protect .. "killactive"))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.exec_cmd(protect .. "forcekillactive"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(scripts .. "/raise-or-launch.sh kitty " .. fileManagerCli))
hl.bind(mainMod .. " + SHIFT + E", hl.dsp.exec_cmd(scripts .. "/raise-or-launch.sh Thunar " .. fileManager))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd(protect .. "togglefloating"))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(protect .. "fullscreen 1"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("btop-workspace exec " .. menu))
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("btop-workspace exec " .. windowSelect))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd(protect .. "pseudo"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd('wtype -s 500 "Green0day" -k Return'))
-- togglesplit became a layoutmsg in Hyprland 0.54; the bare dispatcher is gone
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(protect .. "layoutmsg togglesplit"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(scripts .. "/show-datetime.sh"))
-- Screenshots: save to ~/Pictures/Screenshots and copy to the clipboard.
hl.bind("Print", hl.dsp.exec_cmd(scripts .. "/screenshot.sh full"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd(scripts .. "/screenshot.sh full"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(scripts .. "/screenshot.sh region"))
hl.bind(mainMod .. " + CTRL + C", hl.dsp.exec_cmd(scripts .. "/screenshot.sh region"))
-- Screen recording into ~/Videos/Recordings. The whole family lives on I:
-- Super+I starts, and while a recording is running the same key pauses and
-- resumes it, so one key covers all three states. Region deliberately takes
-- the ALT variant rather than a second SHIFT one: Super+Alt is invariant under
-- the SANWA keyboard's keyd Alt/Super swap (modules/services/keyd.nix), so it
-- survives it. Pause/resume for a region recording is Super+I too.
hl.bind(mainMod .. " + I", hl.dsp.exec_cmd("screen-record screen"), { description = "Record screen / pause / resume" })
hl.bind(mainMod .. " + ALT + I", hl.dsp.exec_cmd("screen-record region"), { description = "Record region / pause / resume" })
hl.bind(mainMod .. " + SHIFT + I", hl.dsp.exec_cmd("screen-record stop"), { description = "Stop recording and save" })
-- Stop recording and throw the file away, as opposed to Super+Shift+I above,
-- which stops and keeps it. Super+Escape is long-form dictation cancel; this is
-- the free SHIFT variant of the same "cancel what is running" idea.
hl.bind(mainMod .. " + SHIFT + ESCAPE", hl.dsp.exec_cmd("screen-record cancel"), { description = "Cancel recording (discard)" })
hl.bind("SUPER + O", hl.dsp.exec_cmd("hyprwhispr-record toggle"), { description = "Speech-to-text" })
hl.bind("CTRL + SHIFT + L", hl.dsp.exec_cmd("hyprwhspr-longform toggle"), { description = "Long-form dictation" })
hl.bind("CTRL + SHIFT + P", hl.dsp.exec_cmd("hyprwhispr-profile toggle"), { description = "Toggle dictation profile" })
hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd("hyprwhspr-longform cancel"))

hl.bind("ALT + SHIFT + B", hl.dsp.exec_cmd(protect .. "alterzorder bottom"))

-- Move focus with mainMod + hjkl
hl.bind(mainMod .. " + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + L", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + K", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + J", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + Tab", hl.dsp.window.cycle_next())
-- The legacy `cyclenext, prev` argument became `next = false`; there is no
-- `prev` field, and an unknown field is silently ignored rather than rejected.
hl.bind(mainMod .. " + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))

-- Move window with mainMod + SHIFT + hjkl. Both a swap and a nudge are bound
-- to each combo, exactly as in the .conf version: the swap applies to tiled
-- windows and the move to floating ones.
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd(protect .. "swapwindow l"))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd(protect .. "swapwindow r"))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd(protect .. "swapwindow u"))
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.exec_cmd(protect .. "swapwindow d"))
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd(protect .. "moveactive -30 0"))
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd(protect .. "moveactive 30 0"))
hl.bind(mainMod .. " + SHIFT + K", hl.dsp.exec_cmd(protect .. "moveactive 0 -30"))
hl.bind(mainMod .. " + SHIFT + J", hl.dsp.exec_cmd(protect .. "moveactive 0 30"))

-- Move to workspace 10 as a "minimized" area
hl.bind("SUPER + M", hl.dsp.exec_cmd(scripts .. "/move-and-tile.sh"))

-- Flip the workspace-10 btop dashboard between this machine and the peer, in
-- its one existing kitty window. B for btop; it carries no navigation meaning
-- inside whatever TUI has focus, unlike the arrows this replaced.
--
-- This is also the rescue for a pane stuck on an unreachable peer: it kills a
-- hung ssh outright rather than waiting out the connect timeout. That works
-- because the toggle reads its current target from the state file rather than
-- from the live connection, so a wedged ssh cannot make it hang in turn — see
-- toggle-host in scripts/btop-workspace.sh.
hl.bind(
  mainMod .. " + B",
  hl.dsp.exec_cmd("btop-workspace toggle-host"),
  { description = "Toggle btop dashboard host" }
)

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
  local key = i % 10 -- 10 maps to key 0
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.exec_cmd(protect .. "movetoworkspace " .. i))
end

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging.
--
-- `{ drag = true }`, not `{ mouse = true }`. These are the legacy `bindm`
-- binds, and `mouse` is not a field of HL.BindOptions at all (see
-- share/hypr/stubs/hl.meta.lua: the flags are `drag` and `click`); an unknown
-- key in a Lua options table is silently ignored. Measured on 0.56.1 by
-- reading the returned keybind back: `{ mouse = true }` yields
-- drag=false click=false -- byte-identical to passing `{}` -- while
-- `{ drag = true }` yields drag=true, and is the only spelling besides
-- `click` that changes anything (both also flip the bind's release flag, which
-- is how a press-and-hold mouse bind is modelled). Hyprland's own shipped
-- reference config (share/hypr/hyprland.lua) has the same mistake, which is
-- where it came from.
--
-- Caveat: `hyprctl binds -j` reports mouse=false for every Lua spelling, while
-- the legacy `bindm` line reports mouse=true, so that view cannot confirm the
-- two are equivalent. Dragging a window by Super+LMB is the check, and it
-- fails visibly and harmlessly if this is still wrong.
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { drag = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { drag = true })

-- Resize active window with Super + Arrow Keys
hl.bind("SUPER + right", hl.dsp.exec_cmd(protect .. "resizeactive 10 0"), { repeating = true })
hl.bind("SUPER + left", hl.dsp.exec_cmd(protect .. "resizeactive -10 0"), { repeating = true })
hl.bind("SUPER + up", hl.dsp.exec_cmd(protect .. "resizeactive 0 -10"), { repeating = true })
hl.bind("SUPER + down", hl.dsp.exec_cmd(protect .. "resizeactive 0 10"), { repeating = true })

-- Laptop multimedia keys for volume and LCD brightness
-- Dynabook X30W-K Fn-row actions that have stable Linux/XF86 events. The
-- firmware may expose these labels differently; keep the bindings on the
-- standard events rather than on model-specific F-row names.
-- Verified on X30W-K: Fn+Esc/3/4 = mute/volume (standard keysyms); Fn+F6/F7 =
-- brightness via the ACPI quirk module; Fn+F3 = XF86Sleep; Fn+F12 = ScrollLock;
-- Fn+F1/F5/S emit Windows chords Super+L/Super+P/Super+Q, already bound
-- elsewhere; Fn+F9 = raw Ctrl+Super+F24/keycode202 (bound below).
-- Fn+F2/F4/F8/Space/Z used to reach only an EC FIFO nothing drained; the
-- toshiba_acpi_dnbk quirk module now drains it via INFO(), so these emit real
-- evdev keys: Fn+F2 = XF86Battery (power-profile cycle), Fn+F4 =
-- XF86AudioMicMute (KEY_SUSPEND remapped to micmute in hwdb to avoid
-- suspending), Fn+F8 = XF86WLAN (mihomo proxy toggle), Fn+Z =
-- XF86KbdLightOnOff (keyboard backlight cycle), Fn+Space = monitor scale cycle.
-- Its native KEY_ZOOMRESET can't pass through keyd's virtual keyboard, so a
-- hwdb rule remaps it to KEY_F21 and the bind is on that keycode (191 + 8 =
-- 199). The XF86WLAN and monitor keys are laptop-only, so these shared binds
-- are inert on the desktop.
hl.bind("XF86ScreenSaver", hl.dsp.exec_cmd("loginctl lock-session"), { locked = true })
hl.bind("XF86Sleep", hl.dsp.exec_cmd("systemctl suspend"), { locked = true })
hl.bind("XF86WLAN", hl.dsp.exec_cmd(scripts .. "/mihomo-toggle.sh"), { locked = true })
hl.bind("XF86Search", hl.dsp.exec_cmd("rofi -show drun -location 2"))
-- Bare XF86TouchpadToggle is Fn+Space (the monitor-scale cycle); Fn+F9 (the
-- actual touchpad toggle) is bound as CTRL+SUPER+F24 -- see the blocks below
-- for why neither can be bound by keycode, and why F24 is the spelling that
-- matches.
-- Fn+F2 cycles power-profiles-daemon profiles; Fn+Z cycles keyboard backlight;
-- Fn+Space cycles the focused monitor's scale.
hl.bind("XF86Battery", hl.dsp.exec_cmd(scripts .. "/power-profile-cycle.sh"))
hl.bind("XF86KbdLightOnOff", hl.dsp.exec_cmd(scripts .. "/kbd-backlight-cycle.sh"))
-- The two laptop keys below used to be bound by raw keycode (`code:199`,
-- `code:202`). THAT DOES NOT WORK UNDER THE LUA CONFIG MANAGER. Measured on
-- 0.56.1: `hl.bind("code:199", ...)` returns "ok" and registers a bind with an
-- empty keysym *and* keycode 0, so it can never match a key event; the legacy
-- hyprlang parser registers the same line with keycode 199. Every other
-- spelling was tried and none sets a keycode -- "CODE:199" and "code199" are
-- rejected as unknown keysyms, and `{ keycode = 199 }` in the options table is
-- ignored (HL.BindOptions has no such field). So there is no keycode form in
-- this Hyprland version and these have to go through keysyms.
--
-- From the compiled `us` keymap (xkbcli compile-keymap --layout us):
--   keycode 199 = <FK21>, symbols [ XF86TouchpadToggle ]
--   keycode 202 = <FK24>, type PC_CONTROL_SUPER_LEVEL2,
--                         symbols [ F24, XF86TouchpadToggle ]
-- so Fn+Space (199, no mods) is XF86TouchpadToggle; Fn+F9 (202 with Ctrl+Super
-- held) would resolve to level 2 -- also XF86TouchpadToggle -- but Hyprland
-- matches the base keysym, so it is bound as F24 and the two never collide.
--
-- Fn+Space arrives as KEY_F21 (hwdb-remapped from KEY_ZOOMRESET, which keyd
-- can't forward).
hl.bind("XF86TouchpadToggle", hl.dsp.exec_cmd(scripts .. "/monitor-scale-cycle.sh"))
-- X30W-K Fn+F9 emits Ctrl+Super+F24. Linux 6.17 corrected this PS/2 scancode
-- from Zenkaku_Hankaku (keycode 93) to F24 (keycode 202).
--
-- Keycode 202 carries [F24, XF86TouchpadToggle] and Fn+F9 arrives with
-- Ctrl+Super held, i.e. at level 2 -- yet Hyprland matches the *base* keysym
-- F24, not the modifier-resolved XF86TouchpadToggle. Measured on this laptop by
-- unbinding one spelling at runtime and pressing the key; `hyprctl binds` gives
-- no answer, it reports either spelling as registered.
hl.bind("CTRL + SUPER + F24", hl.dsp.exec_cmd(scripts .. "/touchpad-toggle.sh"))
hl.bind(
  "XF86AudioRaiseVolume",
  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
  { locked = true, repeating = true }
)
hl.bind(
  "XF86AudioLowerVolume",
  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
  { locked = true, repeating = true }
)
hl.bind(
  "SUPER + minus",
  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
  { locked = true, repeating = true }
)
hl.bind(
  "SUPER + equal",
  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
  { locked = true, repeating = true }
)
hl.bind(
  "CTRL + SHIFT + U",
  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SOURCE@ 5%+"),
  { locked = true, repeating = true }
)
hl.bind(
  "CTRL + SHIFT + D",
  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SOURCE@ 5%-"),
  { locked = true, repeating = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("SUPER + BackSpace", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind(
  "XF86AudioMicMute",
  hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
  { locked = true, repeating = true }
)
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("SUPER + bracketright", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("SUPER + bracketleft", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- --- Automatic Floating ---
--
-- Hyprland 0.56 already floats every window that has a parent and every window
-- that is fixed-size, and its floating layout centres anything that opened
-- without a requested position (CHyprXWaylandManager::shouldBeFloated,
-- CDefaultFloatingAlgorithm::newTarget). That is dialogs, file pickers, modals,
-- X11 transients and cross-client portal dialogs -- xdg-foreign's set_parent_of
-- reaches the same toplevel parent check -- so none of it is repeated here.
--
-- What Hyprland has no equivalent for is a size threshold. No window-rule
-- predicate can see a client's requested size, and once a window is tiled its
-- size *is* the tile's, so the requested size is unrecoverable after the fact.
-- The only place it ever materialises is the floating layout, so candidates are
-- floated on open and the ones that turn out large are tiled again from
-- `window.open`, which fires at the end of CWindow::map() before the window has
-- been composited once -- no flicker, and no daemon that could die and leave
-- the desktop floating.
--
-- The probe deliberately skips the windows this desktop tiles all day and the
-- ones with a float rule of their own: those keep exactly the behaviour they
-- had before this block existed. Adjust the threshold or opt an app out here.
local autofloat = {
  min_width = 600,
  min_height = 400,
  tag = "autofloat-probe",
  never_probe = {
    "kitty", -- yazi, nmtui and the other keybind terminals
    "foot", -- still installed until the migration to kitty settles
    "kitty-main",
    "kitty-float",
    "kitty-btop",
    "brave-browser",
    "chatgpt",
    "115Browser",
    "Thunar",
    "thunar",
    "localsend_app",
    "mandala-wallpaper",
    "imv", -- floated at 1000x700 below, which is over the threshold
  },
}

-- A tag applied by a rule is stored with a trailing "*" appended
-- (CTagKeeper::applyTag), so both spellings have to be accepted.
local function autofloat_probed(w)
  local tags = w.tags
  if type(tags) ~= "table" then
    return false
  end

  for _, tag in ipairs(tags) do
    if tag == autofloat.tag or tag == autofloat.tag .. "*" then
      return true
    end
  end

  return false
end

-- `match.float` is evaluated before any rule effect is applied, so `false` here
-- selects exactly the windows Hyprland did not float on its own -- the probe
-- never second-guesses a native dialog. Declared ahead of the application rules
-- because the last matching rule wins: `float = false` on kitty-main, nmtui and
-- workspace 10 still overrides it.
hl.window_rule({
  name = "autofloat-probe",
  match = {
    class = "negative:^(" .. table.concat(autofloat.never_probe, "|") .. ")$",
    float = false,
  },
  float = true,
  tag = "+" .. autofloat.tag,
})

hl.on("window.open", function(w)
  if not w.floating or not autofloat_probed(w) then
    return
  end

  local size = w.size
  if not size then
    return
  end

  if size.x >= autofloat.min_width and size.y >= autofloat.min_height then
    hl.dispatch(hl.dsp.window.float({ action = "disable", window = w }))
  else
    -- Already centred unless the client asked for a position, which in practice
    -- means X11; kwm centres regardless, so ask for it explicitly.
    hl.dispatch(hl.dsp.window.center({ window = w }))
  end
end)

-- --- Application Rules ---

-- Brave: Fix maximize events
hl.window_rule({
  name = "brave",
  match = { class = "^(brave-browser)$" },
  suppress_event = "maximize",
})

-- File Managers (Thunar)
hl.window_rule({
  name = "thunar",
  match = { class = "^(Thunar|thunar)$" },
  float = true,
})

-- Terminal (Kitty) - floating windows launched via keybindings
hl.window_rule({
  name = "kitty-float",
  match = { class = "^(kitty-float)$" },
  float = true,
  size = "1000 700",
  center = true,
})

-- ...and the only window this desktop makes see-through on its own account.
-- This is the *floating* scratch terminal's treatment, so it is matched on
-- `float` as well as on the class: the same terminal tiled is an ordinary
-- terminal and dims like the rest of them through the inactive-dim rule below.
-- Matching on the class alone left a tiled kitty-float wearing the floating
-- terminal's translucency -- see-through even while focused, which in dark mode
-- meant a full-tile everyday terminal sitting at 0.9.
--
-- That also settles the overlap with inactive-dim: both rules name kitty-float,
-- and they are mutually exclusive by construction because `float = true` here
-- and `float = false` there can never both hold. Only the exclusivity makes
-- this safe -- two rules setting `opacity` do not compose, the later one simply
-- wins -- and it is what makes the declaration order between them irrelevant.
--
-- Both slots carry the same value: translucency is all this terminal gets.
-- Dimming is what marks a *tiled* window as unfocused, and it is spent on the
-- tiled windows by the rule below; a floating scratch terminal is already
-- distinguished by floating, and stacking the mode's dimming on top of its
-- translucency only made it harder to read while it sat unfocused over the
-- wallpaper. So the two-factor product this used to spell out is gone and the
-- second slot repeats the first.
--
-- A mode that wants no translucency sets float_terminal_opacity to 1 and takes
-- the `enabled` branch, rather than relying on the rule being a no-op, because
-- the rule is declared either way -- an undeclared named rule keeps its
-- previous state across a reload, which is what `enabled` exists for here and
-- in the Quiet Graphite set below.
hl.window_rule({
  name = "kitty-float-opacity",
  match = { class = "^(kitty-float)$", float = true },
  enabled = float_terminal_opacity < 1,
  opacity = float_terminal_opacity .. " " .. float_terminal_opacity,
})

-- Everything else that dims. Two things make this narrow on purpose:
--
-- `float = false` is the whole of "a dialog is never see-through". Hyprland
-- floats every parented window itself -- X11 dialogs, transients and
-- override-redirects, xdg-toplevels with a parent, and the cross-client portal
-- dialogs that reach the same check through xdg-foreign -- in
-- CHyprXWaylandManager::shouldBeFloated, and CWindow::map() writes that verdict
-- into the same `m_isFloating` the rule engine matches on, before any window
-- rule is applied. So a browser download window or a file picker is already
-- floating by the time this rule is tested and cannot match it. There is no
-- parent/transient rule predicate in 0.56.1 and no need for one: the answer
-- this desktop wants is "did the compositor float it", not "why". It also stays
-- correct afterwards, because CWindowTarget::setFloating raises
-- RULE_PROP_FLOATING and every rule matched on `float` is re-evaluated at once
-- -- Super+S on a Brave window drops its dimming immediately, and tiling it
-- again brings it back.
--
-- The class list is the second half. kitty-btop is left out deliberately: the
-- workspace-10 dashboard opens with no_initial_focus and is almost never the
-- focused window, so dimming it would just mean a permanently dimmed
-- dashboard. kitty-float is in the list: `float = false` hands the floating
-- scratch terminal to the rule above and keeps the tiled one here, where it
-- gets the same opaque-when-focused treatment as every other tiled terminal.
local inactive_dim_classes = { "brave-browser", "kitty", "kitty-main", "kitty-float", "foot" }

hl.window_rule({
  name = "inactive-dim",
  match = {
    class = "^(" .. table.concat(inactive_dim_classes, "|") .. ")$",
    float = false,
  },
  enabled = inactive_opacity < 1,
  opacity = "1 " .. inactive_opacity,
})

-- Fullscreen is the state where none of that applies: nothing shows through a
-- window that covers the screen, and both slots go back to fully opaque
-- whether the window is floating or tiled underneath. It has to be declared
-- *after* the two rules above, because a repeated property is last-declaration
-- wins rather than a merge -- declared first, as it was, kitty-float-opacity
-- and inactive-dim simply overwrote it and a fullscreen terminal stayed
-- see-through. quiet-graphite-fullscreen at the end of the file is the same
-- exception for the same reason; it sets no opacity, so it does not take this
-- one back.
--
-- `fullscreen` is the boolean predicate: it matches both fullscreen states
-- Hyprland tracks, the maximized one Super+F produces
-- (scripts/protected-dispatch.sh translates it to `mode = "maximized"`, which
-- is what reports as `fullscreen: 1`) and the real fullscreen a client asks
-- for itself. Matching a specific state would need fullscreen_state_internal
-- and would leave the other one dimmed.
--
-- A rule *is* allowed a third opacity slot, and decoration:fullscreen_opacity
-- scales it, which looks like it would do this job without a separate rule. It
-- would not: CWindow reaches for that slot only when the internal mode is
-- FSMODE_FULLSCREEN, so Super+F's maximized fullscreen -- the one this desktop
-- actually produces -- keeps taking the active/inactive slots.
hl.window_rule({
  name = "fullscreen-state",
  match = { fullscreen = 1 },
  border_size = 0,
  rounding = 0,
  opacity = "1.0 1.0",
})

-- Image viewer, the Yazi image opener (home/programs/image-open.nix). Floated
-- at the keybind terminal's geometry so a preview never rearranges the tiling
-- layout, and -- because the dimming rules above only reach tiled windows --
-- never dimmed either. It has to sit in never_probe above, or the auto-float
-- probe would tag it, read back the 1000x700 asked for here, and tile it
-- straight again.
hl.window_rule({
  name = "imv-float",
  match = { class = "^(imv)$" },
  float = true,
  size = "1000 700",
  center = true,
})

-- Main Terminal (Startup) - tile (not fullscreen)
hl.window_rule({
  name = "kitty-main",
  match = { class = "^(kitty-main)$" },
  float = false,
})

-- Network Manager (nmtui)
-- Note: Ensure you launch with `kitty --title nmtui nmtui`
hl.window_rule({
  name = "nmtui-tile",
  match = { title = "^(nmtui)$" },
  float = false,
  pseudo = true,
})

-- LocalSend
hl.window_rule({
  name = "localsend",
  match = { class = "^(localsend_app)$" },
  float = true,
  size = "800 600",
  center = true,
})

-- --- Workspace Specific Rules ---

-- Force tiling on Workspace 10
hl.window_rule({
  name = "workspace-10-force-tile",
  match = { workspace = 10 },
  float = false,
})

-- Persistent full-screen btop dashboard on Super+0 / workspace 10. Keep this
-- after the general workspace-10 rule so its fullscreen state takes precedence.
hl.window_rule({
  name = "btop-dashboard",
  match = { class = "^(kitty-btop)$" },
  workspace = "10 silent",
  float = false,
  border_size = 0,
  rounding = 0,
  no_initial_focus = true,
})

-- ChatGPT Desktop opens on workspace 9 (autostarted by the `chatgpt` user
-- service). A workspace rule only applies when the window maps, so the window
-- stays freely movable afterwards -- nothing pulls it back.
hl.window_rule({
  name = "chatgpt-workspace-9",
  match = { class = "^(chatgpt)$" },
  workspace = "9 silent",
})

-- Quiet Graphite is deliberately an application treatment, not the dark
-- desktop's default window chrome. The shadow engine itself is global, so the
-- first rule suppresses it everywhere and the target rule opts Brave and
-- ChatGPT Desktop back in. State-specific exceptions come last so fullscreen
-- targets and the btop dashboard remain undecorated.
local function quiet_graphite_rule(spec)
  spec.enabled = quiet_graphite_dark
  hl.window_rule(spec)
end

quiet_graphite_rule({
  name = "quiet-graphite-default-no-shadow",
  match = { class = ".*" },
  no_shadow = true,
})

quiet_graphite_rule({
  name = "quiet-graphite-apps",
  match = { class = "^(brave-browser|chatgpt)$" },
  border_size = 2,
  border_color = "rgba(48504Bff) rgba(282E2Aff)",
  rounding = 12,
  no_shadow = false,
})

quiet_graphite_rule({
  name = "quiet-graphite-fullscreen",
  match = { fullscreen = 1 },
  border_size = 0,
  rounding = 0,
  no_shadow = true,
})

quiet_graphite_rule({
  name = "quiet-graphite-btop",
  match = { class = "^(kitty-btop)$" },
  border_size = 0,
  rounding = 0,
  no_shadow = true,
})

-- --- Global Defaults ---

-- Ignore maximize requests from all apps (Global fallback)
hl.window_rule({
  name = "global-no-maximize",
  match = { class = ".*" },
  suppress_event = "maximize",
})

hl.window_rule({
  -- Fix some dragging issues with XWayland
  name = "fix-xwayland-drags",
  match = {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },

  no_focus = true,
})
