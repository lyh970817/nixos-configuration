#!/usr/bin/env bash

# Prevent ordinary window-management shortcuts from changing the dedicated
# btop dashboard. The same shortcuts continue to work for every other window.
if [ "$(hyprctl activewindow -j | jq -r '.class // ""')" = "Alacritty-btop" ]; then
    exit 0
fi

exec hyprctl dispatch "$@"
