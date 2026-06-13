#!/usr/bin/env bash

LOG_FILE="/tmp/auto-hide-floating.log"
SPECIAL_WORKSPACE="special:minimized"

echo "Script started at $(date)" > "$LOG_FILE"

is_floating() {
    local address=$1
    hyprctl clients -j | jq -r ".[] | select(.address == \"$address\") | .floating" 2>/dev/null
}

hide_all_floating() {
    echo "Hiding all floating windows at $(date)" >> "$LOG_FILE"
    
    # Get all floating windows that are NOT in special workspace
    FLOATING_WINDOWS=$(hyprctl clients -j | jq -r '.[] | select(.floating == true and (.workspace.name | startswith("special") | not)) | .address')
    
    for window in $FLOATING_WINDOWS; do
        echo "  Hiding: $window" >> "$LOG_FILE"
        hyprctl dispatch movetoworkspacesilent "$SPECIAL_WORKSPACE,address:$window"
    done
}

last_window=""

while sleep 0.5; do
    CURRENT_WINDOW=$(hyprctl activewindow -j | jq -r '.address // empty')

    if [[ -n "$CURRENT_WINDOW" && "$CURRENT_WINDOW" != "$last_window" ]]; then
        last_window="$CURRENT_WINDOW"
        CURRENT_FLOATING=$(is_floating "$CURRENT_WINDOW")

        echo "Focus changed to: $CURRENT_WINDOW (floating: $CURRENT_FLOATING)" >> "$LOG_FILE"

        # If current window is tiling, hide all floating windows
        if [[ "$CURRENT_FLOATING" == "false" ]]; then
            hide_all_floating
        fi
    fi
done
