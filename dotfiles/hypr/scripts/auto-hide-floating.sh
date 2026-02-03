#!/usr/bin/env bash

LOG_FILE="/tmp/auto-hide-floating.log"
SPECIAL_WORKSPACE="special:minimized"

echo "Script started at $(date)" > "$LOG_FILE"

SOCKET_PATH="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

echo "Socket path: $SOCKET_PATH" >> "$LOG_FILE"

if [[ ! -S "$SOCKET_PATH" ]]; then
    echo "ERROR: Socket not found" >> "$LOG_FILE"
    exit 1
fi

echo "Socket found, connecting..." >> "$LOG_FILE"

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

socat -U - "UNIX-CONNECT:$SOCKET_PATH" | while read -r line; do
    if [[ $line == activewindow* ]]; then
        CURRENT_WINDOW=$(hyprctl activewindow -j | jq -r '.address')
        CURRENT_FLOATING=$(is_floating "$CURRENT_WINDOW")
        
        echo "Focus changed to: $CURRENT_WINDOW (floating: $CURRENT_FLOATING)" >> "$LOG_FILE"
        
        # If current window is tiling, hide all floating windows
        if [[ "$CURRENT_FLOATING" == "false" ]]; then
            hide_all_floating
        fi
    fi
done
