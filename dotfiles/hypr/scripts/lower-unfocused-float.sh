#!/bin/bash

lower_unfocused_floating() {
  hyprctl clients -j | jq -r '.[] | select(.floating == true and .focusHistoryID != 0) | .address' | while read -r addr; do
    hyprctl dispatch alterzorder bottom "address:$addr" 2>/dev/null
  done
}

last_window=""

while sleep 0.5; do
  current_window=$(hyprctl activewindow -j | jq -r '.address // empty')
  if [[ -n "$current_window" && "$current_window" != "$last_window" ]]; then
    last_window="$current_window"
    lower_unfocused_floating
  fi
done
