# `screen-verify` command reference

Every command prints one JSON object to standard output.

## Session lifecycle

```sh
screen-verify begin
screen-verify status --session ID
screen-verify ensure-mode --session ID
screen-verify end --session ID
```

`begin` locks the task to the active light or dark mode. `end` terminates owned
process groups unless they were launched with `--keep-open`, deletes the private
runtime directory, and reconciles a mode displaced for verification.

## Capture targets

```sh
screen-verify capture --session ID
screen-verify capture --session ID --target window
screen-verify capture --session ID --target monitor --monitor DP-1
screen-verify capture --session ID --target all
screen-verify capture --session ID --target region
screen-verify capture --session ID --target region --geometry '10,20 800x600'
```

The default is the focused monitor. Interactive region capture uses `slurp`.
Each successful capture sends a notification after `grim` completes. Captures
live under `$XDG_RUNTIME_DIR/screen-verify/ID` until `end`; abandoned sessions are
purged after 24 hours on the next invocation.

## Test applications

```sh
screen-verify launch --session ID -- executable arg1 arg2
screen-verify launch --session ID --keep-open -- executable arg1
screen-verify adapter --session ID desktop
screen-verify adapter --session ID alacritty
screen-verify adapter --session ID neovim
screen-verify adapter --session ID btop
screen-verify adapter --session ID rofi
screen-verify adapter --session ID notification
```

The desktop adapter reasserts the session mode before inspecting the aggregate
wallpaper, Hyprland, GTK, Mako, and Rofi state. Other adapters provide
repeatable Alacritty, Neovim, btop, Rofi, and Mako test surfaces. Generic launch
uses an argument vector without shell evaluation. The helper records the
process start time and associated Hyprland window so cleanup does not act on a
reused PID or pre-existing window.

## Reversible previews

```sh
screen-verify preview symlink --session ID --target ~/.config/alacritty/current.toml --source /path/to/preview.toml
screen-verify preview gsettings --session ID --schema org.gnome.desktop.interface --key gtk-theme --value "'PreviewTheme'"
screen-verify preview hypr-keyword --session ID --keyword general:gaps_in --value 20
screen-verify preview mako-mode --session ID --mode dark
```

These operations snapshot state into the private session before applying the
override. `end` restores previews in reverse order before deleting the session.
Symlink targets are restricted to the user's home directory. If restoration
fails, cleanup retains the session and its recovery state instead of silently
discarding the snapshot. Use isolated application arguments for Neovim and
other surfaces that can preview without mutating shared runtime state.

## Audit data

Metadata is stored at `$XDG_STATE_HOME/screen-verify/audit.jsonl`, mode `0600`.
Entries expire after 90 days and the file is capped at 1 MiB. It records time,
opaque session ID, event, outcome, capture target, and monitor connector where
applicable. It excludes pixels, text, application identity, window titles,
commands, arguments, working directories, and image paths.
