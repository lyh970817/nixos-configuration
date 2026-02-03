#!/usr/bin/env bash

# Function to check monitors and run the appropriate script
check_monitors() {
  # Check if 'Dasung' is in the output of hyprctl monitors
  if hyprctl monitors | grep -q "DSC"; then
    switch-light
  else
    switch-dark
  fi
}

# Wait for mako to be ready (up to 3 seconds)
for i in $(seq 1 6); do
  pgrep -x mako > /dev/null && makoctl mode > /dev/null 2>&1 && break
  sleep 0.5
done

# Run the initial check
check_monitors

# Listen for monitor events to handle plug/unplug
socat -U - UNIX-CONNECT:"$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
  case "$line" in
  monitoradded* | monitorremoved*)
    sleep 1
    check_monitors
    ;;
  esac
done
