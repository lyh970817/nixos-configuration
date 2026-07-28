# screen-verify bug: ueberzugpp overlay windows escape the staging output

Status: observed and reproduced, cause NOT investigated (deferred to a separate session).

## Symptom

When using `screen-verify launch --session ID -- alacritty -e sh -c 'cd <dir with images> && exec yazi'`,
the Alacritty terminal itself is correctly placed on the session's invisible
staging output/workspace (e.g. `svwsfeeba2a0` on headless output
`svstagefeeba2a0`). However, the `ueberzugpp` child window that Yazi spawns to
render the image preview does **not** follow it there. It reproducibly opens
on the user's real, currently-focused workspace instead (observed: workspace
`4` on the real monitor `eDP-1`), fully exposed to the user's live desktop.

## Reproduction

1. `screen-verify begin` → session `feeba2a005d6558bfffb8c35`, mode `dark`.
2. `screen-verify launch --session <id> -- alacritty -e sh -c 'cd /home/andongni/.nixos-config/assets/wallpapers && exec yazi'`.
3. After ~3s, `hyprctl clients -j` showed:
   - `Alacritty` (pid 2641603) → workspace `svwsfeeba2a0` (correct stage), position far off-screen (staging offset coords).
   - `ueberzugpp_20fa9p1x09` (pid 2641636) → workspace `4` (the real, focused workspace on `eDP-1`), position `[840, 65]` size `[950, 950]`.
4. Repeated with a fresh launch (pid 2643444 / overlay pid 2643480): same result, overlay again on workspace `4`.

## Mitigation attempted (did not fix it)

Tried forcing the overlay's workspace at runtime via:

```
hyprctl keyword windowrulev2 'workspace svwsfeeba2a0, class:^(ueberzugpp_.*)$'
hyprctl keyword windowrulev2 'workspace name:svwsfeeba2a0, class:^(ueberzugpp_.*)$'
```

Both were accepted without a parse error (`ok`) but neither relocated the
overlay — it still opened on workspace `4` on the next launch.

## Notable data points (not yet explained)

- A *different*, concurrently-running screen-verify session (`d46f41fe2490469a921a6b7b`)
  had its own ueberzugpp overlay (pid 2635223) correctly sitting on **its own**
  staging workspace (`svwsd46f41fe`), parented next to its own staged Alacritty
  (pid 2635190). So the leak is not universal/always-on — it appears
  inconsistent or timing-dependent between sessions/launches.
- `ps aux` shows the process as `ueberzugpp layer -so wayland`. `xdotool search
  --pid <overlay_pid>` (via `nix run nixpkgs#xdotool`) returned no match, i.e.
  it is a native Wayland toplevel client, not an Xwayland/override-redirect
  window.
- A `screen-verify capture --session <id> --target focused` taken while the
  leaked overlay window still existed (per `hyprctl clients`) did **not** show
  the overlay in the resulting screenshot — the visible content was just the
  user's own fullscreen terminal on that workspace. This suggests (unconfirmed)
  the overlay was compositor-occluded by the user's fullscreen window at
  capture time, so no visible disruption happened in this particular case. This
  can't be assumed to hold in general — a user without a fullscreen window
  covering that workspace would likely see the overlay flash over their real
  desktop for the ~3s the test window is alive.

## Practical consequence

Any verification task that needs a clean, non-disruptive staged screenshot of
a Yazi/ueberzugpp image preview currently cannot get one through
`screen-verify`'s normal staging flow — the overlay window bypasses the stage
regardless of the parent terminal's placement or an explicit `workspace`
windowrule targeting its class.

## Cleanup performed after each reproduction

- Killed the leaked `alacritty`/`ueberzugpp` process pairs directly
  (`kill -TERM <pid> <pid>`) as soon as observed, minimizing exposure time.
- Cleared all runtime `hyprctl keyword windowrulev2 ...` test rules via
  `hyprctl reload` (config file itself was never modified with these test
  rules, so reload restored the pristine, on-disk rule set). Verified
  afterward that both staging outputs — ours and the other concurrent
  session's (`svstaged46f41fe`) — were unaffected by the reload.
- Ended the session with `screen-verify end --session feeba2a005d6558bfffb8c35`
  (`stage_removed: true`).

No root-cause investigation (Hyprland windowrule application order, ueberzugpp's
own window-placement logic, or screen-verify's stage/focus-switch sequencing)
was performed — left for a follow-up session per instruction.
