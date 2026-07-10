# `codex-screen` command reference

Every command prints one JSON object to standard output.

## Session lifecycle

```sh
codex-screen begin
codex-screen status --session ID
codex-screen ensure-mode --session ID
codex-screen end --session ID
```

`begin` locks the task to the active light or dark mode. `end` terminates owned
process groups unless they were launched with `--keep-open`, deletes the private
runtime directory, and reconciles a mode displaced for verification.

## Capture targets

```sh
codex-screen capture --session ID
codex-screen capture --session ID --target window
codex-screen capture --session ID --target monitor --monitor DP-1
codex-screen capture --session ID --target all
codex-screen capture --session ID --target region
codex-screen capture --session ID --target region --geometry '10,20 800x600'
```

The default is the focused monitor. Interactive region capture uses `slurp`.
Each successful capture sends a notification after `grim` completes. Captures
live under `$XDG_RUNTIME_DIR/codex-screen/ID` until `end`; abandoned sessions are
purged after 24 hours on the next invocation.

## Test applications

```sh
codex-screen launch --session ID -- executable arg1 arg2
codex-screen launch --session ID --keep-open -- executable arg1
codex-screen adapter --session ID desktop
codex-screen adapter --session ID alacritty
codex-screen adapter --session ID neovim
codex-screen adapter --session ID btop
codex-screen adapter --session ID rofi
codex-screen adapter --session ID notification
```

The desktop adapter reasserts the session mode before inspecting the aggregate
wallpaper, Hyprland, GTK, Mako, and Rofi state. Other adapters provide
repeatable Alacritty, Neovim, btop, Rofi, and Mako test surfaces. Generic launch
uses an argument vector without shell evaluation. The helper records the
process start time and associated Hyprland window so cleanup does not act on a
reused PID or pre-existing window.

## Audit data

Metadata is stored at `$XDG_STATE_HOME/codex-screen/audit.jsonl`, mode `0600`.
Entries expire after 90 days and the file is capped at 1 MiB. It records time,
opaque session ID, event, outcome, capture target, and monitor connector where
applicable. It excludes pixels, text, application identity, window titles,
commands, arguments, working directories, and image paths.
