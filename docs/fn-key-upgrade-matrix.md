# Fn-key upgrade verification matrix

This document records the Dynabook X30W-K Fn-key audit after the Linux 6.18
upgrade. It deliberately distinguishes physical evidence, passive runtime
evidence, configuration evidence, and synthetic evidence. A result is not
marked as physically verified unless the captain exercised the real key on the
named active NixOS generation.

## Baseline under diagnosis

- Host: `dynabook-x30wk`
- Kernel: `6.18.42`
- Active generation: `system-263-link`
- Active system: `/nix/store/gswyvc296lkps7nngkzw1827rhpqjir8-nixos-system-dynabook-x30wk-26.11.20260805.b7c2ada`
- Hyprland: `0.56.1`
- keyd: `2.6.0`, active; `/etc/keyd/default.conf` SHA-256
  `09df314e814d8dbaf93c47a9a5181724010621f20de608fd9c7eb0d0833258f3`
- `dynabook-hotkeys-enable` and `power-profiles-daemon`: active
- Rebuild/activation: not run; the serialized rebuild lane has not been
  granted.

keyd grabs the AT keyboard and Toshiba input devices and emits the keyd virtual
keyboard consumed by Hyprland. The Fn modifier itself is firmware-masked. Every
combination configured below is OS-visible either as an AT keyboard event/chord
or a Toshiba ACPI hotkey event; none is classified as firmware-only.

## Matrix

“Pending” means that the final combined generation has not yet been activated
and physically gated. The rebuild evidence column applies to every row and is
currently “none (lane not granted).”

| Combination | Initiating trigger and observed event/code | Masking condition | Intended desktop path and observable outcome | Result before | Result after | Exact fix | Rebuild/activation evidence | Functional verification evidence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Fn+Esc | Physical AT event0: scan `0xa0`; `EV_KEY KEY_MUTE` code 113. Fifteen complete press/release pairs were captured at 02:16:14–02:16:22 CST. | Fn is firmware-masked. keyd forwards code 113. The live Hyprland bind was repeat-enabled (`bindel`). | keyd virtual keyboard → `XF86AudioMute` → `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` → speaker mute changes once. | **FAIL:** captain reported unchanged. Passive Hyprland tracing recorded three successful `wpctl` executions for the reported one physical activation. | Pending rebuilt physical retest. | Change only this toggle from `bindel` to locked, non-repeating `bindl`. | None; lane not granted. | Raw trace SHA-256 `f9857269fb496caa46184bff8e3cbc464fe8d770e937994d9ce943bdecf310b8`; exec trace SHA-256 `10fe011bf7be7c68be388af83ee42f8fd467eab390fe318958878c74acff5719`. `wpctl` exited 0 and WirePlumber persisted the muted default speaker route at 02:21:46 CST. Post-fix physical gate pending. |
| Fn+3 | AT keyboard `EV_KEY KEY_VOLUMEDOWN`, code 114. | Fn firmware-masked; keyd forwards the media key. | `XF86AudioLowerVolume` → `wpctl set-volume … 5%-` → sink volume decreases. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Earlier volume-path checks were synthetic and are not physical proof. |
| Fn+4 | AT keyboard `EV_KEY KEY_VOLUMEUP`, code 115. | Fn firmware-masked; keyd forwards the media key. | `XF86AudioRaiseVolume` → `wpctl set-volume -l 1 … 5%+` → sink volume increases. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Earlier volume-path checks were synthetic and are not physical proof. |
| Fn+F1 | AT keyboard raw chord `KEY_LEFTMETA` 125 + `KEY_L` 38. | Fn becomes a firmware-generated Windows chord; ordinary Hyprland modifiers apply. | `SUPER+L` → `movefocus r` → focus moves right. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Configuration/history path established; physical outcome pending. |
| Fn+F2 | Toshiba scan `0x13c` → `KEY_BATTERY`, code 236. | Toshiba ACPI FIFO must be drained by `toshiba_acpi_dnbk`; keyd forwards the code. | `XF86Battery` → `power-profile-cycle.sh` → power profile and notification change. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Driver sparse-keymap and live service establish the path; physical outcome pending. |
| Fn+F3 | Toshiba scan `0x13d` → `KEY_SLEEP`, code 142. | Toshiba FIFO/driver and keyd; locked bind remains active under an inhibitor. | `XF86Sleep` → `systemctl suspend` → system suspends. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Authoritative driver/configuration path established. Destructive session outcome requires coordinated physical verification. |
| Fn+F4 | Toshiba scan `0x13e`, hwdb-remapped from `KEY_SUSPEND` 205 to `KEY_MICMUTE` 248. | hwdb remap prevents accidental suspend; Toshiba FIFO and keyd must forward it. | `XF86AudioMicMute` → `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` → microphone mute changes. | Current-generation physical gate pending. | Pending. | None; do not infer the Fn+Esc repeat failure without physical evidence. | None; lane not granted. | Earlier microphone-path checks were synthetic and are not physical proof. |
| Fn+F5 | AT keyboard raw chord `KEY_LEFTMETA` 125 + `KEY_P` 25. | Fn becomes a firmware-generated Windows chord. | `SUPER+P` → `protected-dispatch.sh pseudo` → focused window pseudo state changes. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Configuration/history path established; physical outcome pending. |
| Fn+F6 | Toshiba scan `0x140` → `KEY_BRIGHTNESSDOWN`, code 224. | Toshiba FIFO/driver and keyd. | `XF86MonBrightnessDown` → `brightnessctl … 5%-` → panel brightness decreases. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Earlier brightness-path checks were synthetic and are not physical proof. |
| Fn+F7 | Toshiba scan `0x141` → `KEY_BRIGHTNESSUP`, code 225. | Toshiba FIFO/driver and keyd. | `XF86MonBrightnessUp` → `brightnessctl … 5%+` → panel brightness increases. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Earlier brightness-path checks were synthetic and are not physical proof. |
| Fn+F8 | Toshiba scan `0x142` → `KEY_WLAN`, code 238. | Toshiba FIFO/driver and keyd. This action changes the proxy carrying the agent connection. | `XF86WLAN` → `mihomo-toggle.sh` → proxy state/notification changes. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Configuration and driver path established. No synthetic or uncoordinated functional execution is permitted. |
| Fn+F9 | Upgraded AT path: `KEY_LEFTCTRL` 29 + `KEY_LEFTMETA` 125 + `KEY_F24` 194, XKB/Hyprland keycode 202. Linux 6.17 corrected the former F24 mapping from `KEY_ZENKAKUHANKAKU` 85/keycode 93. | Firmware emits a raw chord. The old Hyprland code-93 bind masks the upgraded code-202 trigger by failing to match it. | `CTRL+SUPER+code:202` → `touchpad-toggle.sh` → touchpad enabled state and notification change. | **FAIL established from authoritative kernel divergence/config evidence.** | Pending final combined-generation regression test. | Existing prerequisite commit `c23e8a91` changes `code:93` to `code:202`; do not duplicate it in this branch. | None in this branch; prerequisite is not yet on `master`. | Synthetic corrected-chord check against the old live bind did not change state and is synthetic only. Physical regression gate pending after the prerequisite and Fn+Esc fix coexist. |
| Fn+F12 | AT keyboard `KEY_SCROLLLOCK`, code 70. | Fn firmware-masked; keyd forwards the key. No Hyprland command is configured. | Scroll Lock reaches the desktop/application as a normal key event. | Current-generation physical event gate pending. | Pending. | None. | None; lane not granted. | Configuration/history path established; physical event pending. |
| Fn+Z | Toshiba scan `0x12c` → `KEY_KBDILLUMTOGGLE`, code 228. | Toshiba FIFO/driver and keyd. | `XF86KbdLightOnOff` → `kbd-backlight-cycle.sh` → keyboard backlight level and notification change. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Earlier keyboard-backlight checks were synthetic and are not physical proof. |
| Fn+Space | Toshiba scan `0x139`, hwdb-remapped from `KEY_ZOOMRESET` 420 to `KEY_F21` 191; Hyprland keycode 199. | Native code 420 exceeds keyd's virtual keyboard capability; the hwdb remap is required before keyd. | `code:199` → `monitor-scale-cycle.sh` → focused monitor scale changes. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Earlier monitor-scale check was synthetic and is not physical proof. |
| Fn+S | AT keyboard raw chord `KEY_LEFTMETA` 125 + `KEY_Q` 16. | Fn becomes a firmware-generated Windows chord; protected-dispatch masking rules still apply. | `SUPER+Q` → `protected-dispatch.sh killactive` → eligible focused window closes. | Current-generation physical gate pending. | Pending. | None. | None; lane not granted. | Configuration/history path established; physical outcome pending. |

## Fn+Esc causal evidence

The initiating trigger, masking condition, and symptom are separate:

1. Trigger: the physical Fn+Esc burst emitted scan `0xa0` and code 113 on AT
   event0. Toshiba event1 emitted nothing because this combination is an AT
   keyboard path, not a Toshiba ACPI FIFO path.
2. Remapping: keyd reproduced every code-113 press/release edge on its virtual
   keyboard. There was no lost kernel or keyd event.
3. Desktop dispatch: Hyprland spawned the configured shell and the installed
   `/run/current-system/sw/bin/wpctl`; every captured process exited 0.
4. Symptom: the captain reported no observable mute change.
5. Mask: the live binding was `bindel`; `e` makes a bind repeat while held. The
   passive exec trace captured three toggle commands for the captain's reported
   single activation. The [Hyprland bind documentation](https://wiki.hypr.land/Configuring/Basics/Binds/)
   uses repeat for volume changes but locked-only for mute toggles.
6. Smallest counterfactual: retain `l` and remove only `e` from Fn+Esc. This
   preserves operation under an input inhibitor while preventing one activation
   from dispatching a toggle repeatedly. A rebuild and one unambiguous physical
   retest are required before calling the correction successful.

The captain's previously reported pass was explicitly retracted and is not
evidence. All ydotool, direct `wpctl`, brightness, power-profile, keyboard-light,
and monitor-scale checks performed before the safety stop are synthetic; they
only establish downstream command capability and never satisfy a physical gate.

## Remaining gates

1. Commit the smallest Fn+Esc correction before any apply.
2. Wait for the sole serialized rebuild lane and run only the explicitly
   authorized apply.
3. Record the resulting generation/profile, kernel/input devices, loaded keyd
   configuration/service state, and live Hyprland bindings.
4. Obtain one fresh, unambiguous physical Fn+Esc retest on that generation.
5. After prerequisite commit `c23e8a91` is present in the same final generation,
   physically regression-test Fn+F9 and complete the remaining rows without
   unsafe or uncoordinated state changes.
