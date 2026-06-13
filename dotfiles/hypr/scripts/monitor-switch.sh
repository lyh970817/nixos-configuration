#!/usr/bin/env bash

current_mode() {
  if hyprctl monitors | grep -q "DSC"; then
    echo "light"
  else
    echo "dark"
  fi
}

apply_mode() {
  case "$1" in
  light) switch-light ;;
  dark) switch-dark ;;
  esac
}

# Wait for mako to be ready (up to 3 seconds)
for i in $(seq 1 6); do
  pgrep -x mako > /dev/null && makoctl mode > /dev/null 2>&1 && break
  sleep 0.5
done

# Run the initial check
mode=$(current_mode)
apply_mode "$mode"

# Launch terminal at boot if in Dark Mode (no DSC monitor)
if [ "$mode" = "dark" ]; then
  alacritty --class Alacritty-main --command tmux new-session -A -s main &
fi

# Poll monitor state so this script has no socat runtime dependency.
while sleep 2; do
  next_mode=$(current_mode)
  if [ "$next_mode" != "$mode" ]; then
    mode="$next_mode"
    apply_mode "$mode"
  fi
done
