---
name: visual-verification
description: Visually verify themes, colorschemes, fonts, wallpaper, bars, notifications, terminal appearance, and other rendered desktop changes. Use automatically for any visual change request.
---

# Visual verification

Treat visual verification as part of done for every visual change.

## 1. Lock the task mode

Run `codex-screen begin`, retain its JSON `session` value, and announce visual
verification before the first capture. The returned light or dark mode is the
only mode this task may change or assess. If the live mode changes, run
`codex-screen ensure-mode --session ID` before previewing or capturing.

Completion criterion: every planned edit is scoped to the session's starting
mode, unless the user explicitly requested both modes.

## 2. Preview reversibly

Use a runtime override, application reload, or isolated temporary config only
when its inverse is reliable. Apply symlinked themes, GTK settings, Hyprland
keywords, and Mako modes through `codex-screen preview`; the session snapshots
and restores them. Use the normal commit-and-rebuild path when a supported safe
preview does not exist.

Launch test surfaces through `codex-screen adapter` or `codex-screen launch` so
the session owns them. Read [COMMANDS.md](COMMANDS.md) when choosing targets,
adapters, or cleanup flags.

Completion criterion: the preview can be restored, and pre-existing processes
and windows remain outside session ownership.

## 3. Capture and inspect

Use `codex-screen capture --session ID`; focused-monitor capture is the default.
Inspect the returned image path with the local image viewer. Iterate on
objective defects: theme loading, fallback colors, contrast, legibility,
clipping, geometry, and current-mode consistency. Put subjective aesthetic
choices to the user.

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

Use `codex-screen end --session ID` on success, error, cancellation, or timeout.
It closes only owned test processes, removes ephemeral captures, and restores a
mode displaced for verification. Use `--keep-open` only when the user wants a
launched test instance preserved.

Completion criterion: the session directory is gone and temporary visual state
has been restored.

## Safety boundary

This is a cooperative policy for a same-user agent, not a hostile-process
sandbox. Route captures through `codex-screen`; its notification and audit
metadata make capture visible. Keep commands, arguments, application identity,
window titles, captured text, and image paths out of persistent audit data.
