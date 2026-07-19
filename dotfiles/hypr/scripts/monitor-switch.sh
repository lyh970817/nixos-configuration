#!/usr/bin/env bash

# Persist the last monitor-derived mode so switching is edge-triggered on real
# plug/unplug events. A mode that arrives via an incoming push runs switch-*
# directly (not this script), so it never touches this state and never bounces
# back to the peer.
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/theme-monitor-mode"

current_mode() {
  # Monitor presence is the sole automatic theme trigger. The DSC e-ink
  # display selects light mode; its absence selects dark mode. This setup does
  # not use Darkman's time, location, or GeoClue transition mechanisms.
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

# Run the initial check. Always apply the theme on startup to establish the
# live Hyprland/wallpaper state and seed the state file, but do not push at
# boot: pushes happen only on genuine plug/unplug edges (and from theme-toggle).
mode=$(current_mode)
apply_mode "$mode"
mkdir -p "$(dirname "$STATE_FILE")"
printf '%s\n' "$mode" > "$STATE_FILE"

# Launch terminal at boot if in Dark Mode (no DSC monitor)
if [ "$mode" = "dark" ]; then
  alacritty --class Alacritty-main --command tmux new-session -A -s main &
fi

# Poll monitor state so this script has no socat runtime dependency. Apply the
# theme scripts directly rather than asking Darkman to schedule a transition.
# Only a change relative to the stored monitor-derived mode is a real edge: on
# such an edge, record it, apply locally, then notify the peer.
while sleep 2; do
  desired=$(current_mode)
  stored=$(cat "$STATE_FILE" 2>/dev/null || true)
  if [ "$desired" != "$stored" ]; then
    printf '%s\n' "$desired" > "$STATE_FILE"
    apply_mode "$desired"
    theme-push "$desired"
  fi
done
