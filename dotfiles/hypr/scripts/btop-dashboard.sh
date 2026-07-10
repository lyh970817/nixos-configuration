#!/usr/bin/env bash

# Keep the workspace dashboard alive if btop is exited with q, Ctrl+C, or a
# process signal. Killing the containing Alacritty process remains an explicit
# administrative escape hatch.

# Hyprland does not apply a static fullscreen rule to this silently-created,
# initially-unfocused window. Focus it once after mapping, enter compositor
# fullscreen, then restore the workspace that was active during startup.
(
    starting_workspace=$(hyprctl activeworkspace -j | jq -r '.id')

    for _ in {1..20}; do
        dashboard_address=$(hyprctl clients -j | jq -r --argjson pid "$PPID" \
            '.[] | select(.pid == $pid) | .address' | head -1)
        if [ -n "$dashboard_address" ]; then
            hyprctl dispatch focuswindow "address:$dashboard_address"
            hyprctl dispatch fullscreen 1
            hyprctl dispatch workspace "$starting_workspace"
            exit 0
        fi
        sleep 0.1
    done
) &

while true; do
    btop
    sleep 0.25
done
