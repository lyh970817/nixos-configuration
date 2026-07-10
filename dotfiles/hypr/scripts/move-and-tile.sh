#!/usr/bin/env bash

# Keep the dedicated btop dashboard fixed on workspace 10.
if [ "$(hyprctl activewindow -j | jq -r '.class // ""')" = "Alacritty-btop" ]; then
    exit 0
fi

# Get the active window address
window=$(hyprctl activewindow -j | jq -r '.address')

# Check if window is floating
is_floating=$(hyprctl activewindow -j | jq -r '.floating')

# If it was floating, make it tiled
if [ "$is_floating" = "true" ]; then
    hyprctl dispatch togglefloating address:$window
fi

# Move to workspace 10
hyprctl dispatch movetoworkspacesilent 10
