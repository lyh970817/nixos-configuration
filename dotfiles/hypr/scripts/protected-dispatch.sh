#!/usr/bin/env bash

# Prevent ordinary window-management shortcuts from changing the dedicated
# btop dashboard. The same shortcuts continue to work for every other window.
if [ "$(hyprctl activewindow -j | jq -r '.class // ""')" = "Alacritty-btop" ]; then
    exit 0
fi

# Workspace 10 is reserved for the managed dashboard while its guard is locked.
if [ "${1:-}" = "movetoworkspace" ] && [ "${2:-}" = "10" ] && btop-workspace is-locked; then
    exit 0
fi

exec hyprctl dispatch "$@"
