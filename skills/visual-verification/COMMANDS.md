# `screen-verify` command reference

Every command prints one JSON object to standard output.

## Session lifecycle

```sh
screen-verify begin
screen-verify stage --session ID
screen-verify status --session ID
screen-verify ensure-mode --session ID
screen-verify end --session ID
```

`begin` locks the task to the active light or dark mode. `stage` explicitly
creates or returns the session's invisible headless staging output; `launch`
and `adapter` also create it lazily. `status` reports whether a stage is
active and its output name. `end` terminates owned process groups unless
launched with `--keep-open`, deletes the private runtime directory, removes
the staging output (`stage_removed`), and reconciles a mode displaced for
verification.

## Capture targets

```sh
screen-verify capture --session ID
screen-verify capture --session ID --target stage
screen-verify capture --session ID --target window
screen-verify capture --session ID --target monitor --monitor DP-1
screen-verify capture --session ID --target all
screen-verify capture --session ID --target region
screen-verify capture --session ID --target region --geometry '10,20 800x600'
```

The default is the session's stage if one exists, otherwise the focused
monitor. Under a stage, `--target window` captures the most recently launched
owned window, not the user's focused window; `--target focused`/`monitor`/
`region` inspect the real, visible desktop, and `--target all` includes the
staging output. Interactive region capture uses `slurp`. Each successful
capture sends a notification after `grim` completes. Captures live under
`$XDG_RUNTIME_DIR/screen-verify/ID` until `end`; abandoned sessions are purged
after 24 hours on the next invocation.

## Test applications

```sh
screen-verify launch --session ID -- executable arg1 arg2
screen-verify launch --session ID --keep-open -- executable arg1
screen-verify launch --session ID --no-stage -- executable arg1
screen-verify adapter --session ID desktop
screen-verify adapter --session ID alacritty
screen-verify adapter --session ID neovim
screen-verify adapter --session ID btop
screen-verify adapter --session ID rofi
screen-verify adapter --session ID notification
```

The desktop adapter never creates a stage; it reasserts the session mode before
inspecting the real aggregate wallpaper, Hyprland, GTK, Mako, and Rofi state.
Other adapters spawn onto the session's invisible staging output by default;
pass `--no-stage` to use the user's real, visible workspace instead. `rofi` is
a layer surface exempt from workspace rules, so its adapter's `-m` placement on
the stage does not stop it grabbing the keyboard — its launch result carries a
`warning` field noting this. `notification` (mako) toasts always land on the
real screen and cannot be relocated. A staged launch crosses Hyprland's `exec`
shell and a screen-verify trampoline, every argument shell-quoted so none is
evaluated; `--no-stage` uses no shell. It inherits Hyprland's cwd, environment,
and PATH, not screen-verify's, so `./result/bin/...` and `nix-shell`/direnv
PATH bite. Hyprland's exec workspace rule only places the first window of the
tree, so the trampoline marks the whole tree with a session environment
variable, a detached per-session watcher moves owned windows that open off the
stage back onto it, and `launch` sweeps stragglers after the primary window
resolves; the launch `warning` field reports a primary window still off the
stage after that. Generic launch records the process start time and associated
Hyprland window so cleanup does not act on a reused PID or pre-existing window.

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
opaque session ID, event (including `stage`), outcome, capture target, and
monitor connector where applicable, with the staging output name recorded in
the existing `monitor` field. It excludes pixels, text, application identity,
window titles, commands, arguments, working directories, and image paths.
