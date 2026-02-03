#!/bin/bash

# Listen to window focus events and lower unfocused floating windows
handle() {
  case $1 in
    activewindow*)
      # When a window gets focus, lower all other floating windows
      hyprctl clients -j | jq -r '.[] | select(.floating == true and .focusHistoryID != 0) | .address' | while read addr; do
        hyprctl dispatch alterzorder bottom "address:$addr" 2>/dev/null
      done
      ;;
  esac
}

socat -U - UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | while read -r line; do handle "$line"; done
