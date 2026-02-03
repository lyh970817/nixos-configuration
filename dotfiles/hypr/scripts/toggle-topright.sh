#!/usr/bin/env bash

# Get active window info
win=$(hyprctl activewindow -j)
echo "Full window info:"
echo $win | jq '.'

win_x=$(echo $win | jq -r '.at[0]')
win_y=$(echo $win | jq -r '.at[1]')
win_w=$(echo $win | jq -r '.size[0]')
win_h=$(echo $win | jq -r '.size[1]')

echo "Window position: $win_x, $win_y"
echo "Window size: $win_w x $win_h"

# Get monitor info
mon_id=$(echo $win | jq -r '.monitor')
mon=$(hyprctl monitors -j | jq ".[] | select(.id == $mon_id)")
echo "Monitor info:"
echo $mon | jq '.'

mon_w=$(echo $mon | jq -r '.width')
mon_h=$(echo $mon | jq -r '.height')

echo "Monitor size: $mon_w x $mon_h"

# Calculate target
target_x=$((mon_w - win_w - 20))
target_y=20

echo "Calculated target: $target_x, $target_y"
