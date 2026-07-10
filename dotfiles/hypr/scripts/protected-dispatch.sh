#!/usr/bin/env bash

# Prevent ordinary window-management shortcuts from changing the dedicated
# btop dashboard. The same shortcuts continue to work for every other window.
if [ "$(hyprctl activewindow -j | jq -r '.class // ""')" = "Alacritty-btop" ]; then
    exit 0
fi

# Foreground windows shown on workspace 10 live in its overlay workspace. Move
# there silently first, then follow the window by switching to the btop base.
if [ "$1" = "movetoworkspace" ] && [ "$2" = "10" ]; then
    hyprctl dispatch movetoworkspacesilent special:btop-overlay
    exec hyprctl dispatch workspace 10
fi

exec hyprctl dispatch "$@"
