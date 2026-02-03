#!/usr/bin/env bash
# Save as ~/.config/hypr/scripts/terminal-here.sh

# Get the PID of the active window
PID=$(hyprctl activewindow -j | jq -r '.pid')

if [ -z "$PID" ] || [ "$PID" = "null" ]; then
    $TERMINAL &
    exit 0
fi

# Function to check if a directory is valid for opening a terminal
is_valid_dir() {
    local dir="$1"
    # Check if directory exists and is not empty
    [ -n "$dir" ] || return 1
    [ -d "$dir" ] || return 1
    
    # Exclude /proc and /sys directories
    [[ "$dir" =~ ^/proc ]] && return 1
    [[ "$dir" =~ ^/sys ]] && return 1
    
    # Exclude /tmp unless it's a subdirectory
    [ "$dir" = "/tmp" ] && return 1
    
    return 0
}

# Get the working directory
# First try the main PID
CWD=$(readlink /proc/$PID/cwd 2>/dev/null)

# If that's just HOME or invalid, check all children for a better directory
if ! is_valid_dir "$CWD" || [ "$CWD" = "$HOME" ]; then
    for child in $(pgrep -P $PID); do
        child_cwd=$(readlink /proc/$child/cwd 2>/dev/null)
        # Use the first child that has a valid directory that's not HOME
        if is_valid_dir "$child_cwd" && [ "$child_cwd" != "$HOME" ]; then
            CWD="$child_cwd"
            break
        fi
    done
fi

# Fallback to HOME if nothing found
if ! is_valid_dir "$CWD"; then
    CWD="$HOME"
fi

# Launch terminal in that directory
TERM_NAME=$(basename "$TERMINAL")
case "$TERM_NAME" in
    alacritty|foot)
        $TERMINAL --working-directory "$CWD" &
        ;;
    kitty)
        $TERMINAL --directory "$CWD" &
        ;;
    wezterm)
        $TERMINAL start --cwd "$CWD" &
        ;;
    *)
        (cd "$CWD" && $TERMINAL) &
        ;;
esac
