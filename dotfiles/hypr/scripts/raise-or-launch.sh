#!/usr/bin/env bash
# raise-or-launch.sh CLASS COMMAND [ARGS...]
#
# If a window whose class equals CLASS (case-insensitive) already exists, focus
# it. Otherwise launch COMMAND (through the btop-workspace guard, exactly as a
# plain app-launch bind would).
#
# This makes an app-launch keybinding idempotent and — more importantly — lets
# you recover an app that hid itself to the system tray. Closing such an app
# (e.g. an accidental Super+Q) destroys its Wayland window, so it is no longer a
# hyprctl client and cannot be focused or listed by the window switcher. But
# these apps are single-instance: relaunching raises the hidden window instead
# of spawning a duplicate.
set -uo pipefail

cls="${1:-}"
shift || true

if [ -z "$cls" ] || [ "$#" -eq 0 ]; then
    echo "usage: raise-or-launch.sh <class> <command> [args...]" >&2
    exit 2
fi

addr=$(
    hyprctl clients -j | jq -r --arg cls "$cls" '
        map(select(
            ((.class // "")        | ascii_downcase) == ($cls | ascii_downcase)
            or ((.initialClass // "") | ascii_downcase) == ($cls | ascii_downcase)
        ))
        | min_by(.focusHistoryID)
        | .address // empty
    '
)

if [ -n "$addr" ]; then
    # `hyprctl dispatch` evaluates its argument as Lua under the Lua config
    # manager, so the legacy `focuswindow address:...` form is gone; hypr-ipc
    # sends whichever dialect the running compositor speaks. The legacy argv
    # after `--` is TRANSITIONAL (see pkgs/hypr-ipc.nix).
    exec hypr-ipc dispatch "hl.dsp.focus({ window = \"address:$addr\" })" \
        -- focuswindow "address:$addr"
fi

exec btop-workspace exec "$@"
