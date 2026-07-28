# screen-verify bug: ueberzugpp overlay windows escape the staging output

Status: root-caused and fixed; see "Root cause and fix" at the end.

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

## Root cause and fix

### Root cause

`stage_spawn` places windows via `hyprctl dispatch exec "[workspace
name:svws<id> silent; noinitialfocus] <command>"`. In Hyprland 0.53.1 that
exec rule block is matched to the spawned tree through an inherited
environment token (`HL_EXEC_RULE_TOKEN`), but it is **one-shot**: the rule is
unregistered as soon as the first window of the tree maps, and it expires 60
seconds after the spawn regardless. So the staged Alacritty consumes the rule
when it maps, and when Yazi later spawns `ueberzugpp` — seconds later, or
whenever the user navigates onto an image — that window maps with no rule in
force and lands on the user's real focused workspace. This also explains the
inconsistency between sessions: whether an overlay leaks depends only on
whether it maps before or after the first window of its tree.

The `windowrulev2` mitigation could never have worked, twice over:
`windowrulev2` no longer exists in 0.53.1 (the v3 syntax is `windowrule ...
match:class ...`), and `hyprctl keyword` exits 0 and prints `ok` even for a
rejected keyword, which is why the attempt looked accepted. Even a correct v3
workspace rule would not have helped: workspace window rules act at map time
only and cannot move an already-open window, and Hyprland has no pid- or
tree-based matching that would catch a future child's window.

### Fix

Three cooperating parts, none of which can move a window the session does not
positively own:

1. **Session marker.** The staged trampoline exports
   `SCREEN_VERIFY_STAGE=<session>` before its `exec`, so every descendant —
   including double-forked, reparented ones — carries the session identity in
   `/proc/<pid>/environ`, where it survives any break in the pid tree.
2. **Per-session stage watcher.** `ensure_stage` starts a detached
   `stage-watch` helper (recorded in `session.json` with pid and start time)
   the moment the stage exists. It reads `openwindow` events from Hyprland's
   socket2 and, for each window that is off the staging workspace and owned —
   marker in `/proc/<pid>/environ`, or descendant of a recorded staged spawn —
   dispatches `movetoworkspacesilent name:<workspace>,address:0x<address>`.
   It exits on its own when the stage record or session disappears; `end`
   also SIGTERMs it behind the usual start-time guard.
3. **Post-launch sweep.** `launch` sweeps `hyprctl clients -j` after the
   primary window resolves and moves any owned, off-stage window back,
   covering windows that mapped before the watcher could act. The launch
   `warning` field now describes what the sweep could not fix.
