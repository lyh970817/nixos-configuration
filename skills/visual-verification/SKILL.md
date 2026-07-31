---
name: visual-verification
description: Use only when correctness depends on inspecting rendered pixels or live GUI behavior that CLI checks cannot establish, such as actual layout, typography, contrast, clipping, composition, or visual interaction. Do not use for changes whose correctness is established by tests, config evaluation, logs, command output, or machine-readable desktop state.
---

# Visual verification

Use this skill only when a CLI-only check cannot establish the acceptance
criterion. The fact that a change affects something visible is not sufficient.

Before starting a session, apply this gate:

1. Identify what must be proven for the task to be correct.
2. Decide whether tests, config evaluation, logs, command output, or
   machine-readable desktop state can prove it. A CLI command that captures a
   screenshot does not make pixel inspection CLI-only; use this skill when the
   captured result still needs visual inspection.
3. If those checks are sufficient, do not invoke `screen-verify`; use the
   normal CLI verification for the change.
4. If the acceptance criterion requires inspecting rendered pixels or live GUI
   behavior, continue with this skill and treat visual inspection as part of
   done.

Do not use this skill solely for configuration presence, package availability,
service status, launcher definitions, keybindings, numeric options, or other
behavior with an authoritative CLI, test, log, or state inspection.

## 1. Lock the task mode

Run `screen-verify begin`, retain its JSON `session` value, and announce visual
verification before the first capture. The returned light or dark mode is the
only mode this task may change or assess. If the live mode changes, run
`screen-verify ensure-mode --session ID` before previewing or capturing.

Completion criterion: every planned edit is scoped to the session's starting
mode, unless the user explicitly requested both modes.

## 2. Preview reversibly

Use a runtime override, application reload, or isolated temporary config only
when its inverse is reliable. Apply symlinked themes, GTK settings, Hyprland
keywords, and Mako modes through `screen-verify preview`; the session snapshots
and restores them. Use the normal commit-and-rebuild path when a supported safe
preview does not exist.

Launch test surfaces through `screen-verify adapter` or `screen-verify launch` so
the session owns them; by default they spawn on the session's staging output,
away from the user's real workspace. Staged trees are marked, and a per-session
watcher plus a post-launch sweep pull late child windows — image-preview
overlays, dialogs — back onto the stage. Isolation is still not guaranteed — a
layer surface such as `rofi` grabs the keyboard wherever it opens, and a window
can stay off the staging workspace — so check the launch result's `warning`
field. Pass `--no-stage` only when the real desktop itself is under test. Read
[COMMANDS.md](COMMANDS.md) when choosing targets, adapters, or cleanup flags.

Completion criterion: the preview can be restored, and pre-existing processes
and windows remain outside session ownership.

## 3. Capture and inspect

Use `screen-verify capture --session ID`; the default target is the session's
stage when one exists, otherwise the focused monitor. To verify the real
desktop itself — wallpaper, bars, notifications — use `--target focused` or
launch with `--no-stage`. Inspect the returned image path with the local image
viewer. Iterate on objective defects: theme loading, fallback colors,
contrast, legibility, clipping, geometry, and current-mode consistency. Put
subjective aesthetic choices to the user.

Completion criterion: the rendered result, rather than screenshot creation
alone, satisfies the visual request in the starting mode.

## 4. Persist and verify

Write the source-of-truth configuration for the starting mode only. Commit it
before the authoritative NixOS rebuild, then capture and inspect the installed
result again. A visual-preview exception never authorizes an uncommitted Home
Manager activation or NixOS rebuild.

Completion criterion: the committed, rebuilt result has been visually
inspected and objective defects are resolved.

## 5. Clean up

Use `screen-verify end --session ID` on success, error, cancellation, or timeout.
It closes only owned test processes, removes ephemeral captures, and restores a
mode displaced for verification. Use `--keep-open` only when the user wants a
launched test instance preserved.

Completion criterion: the session directory is gone and temporary visual state
has been restored.

## Safety boundary

This is a cooperative policy for a same-user agent, not a hostile-process
sandbox. Route captures through `screen-verify`; its notification and audit
metadata make capture visible. Keep commands, arguments, application identity,
window titles, captured text, and image paths out of persistent audit data.
