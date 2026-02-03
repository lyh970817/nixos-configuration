#!/usr/bin/env bash

# Get current workspace ID
CURRENT_WS=$(hyprctl activeworkspace -j | jq -r '.id')

# Get all windows in special:minimized workspace
MINIMIZED_WINDOWS=$(hyprctl clients -j | jq -r '.[] | select(.workspace.name == "special:minimized") | .address')

# Move each window to current workspace
for window in $MINIMIZED_WINDOWS; do
    hyprctl dispatch movetoworkspace "$CURRENT_WS,address:$window"
done
