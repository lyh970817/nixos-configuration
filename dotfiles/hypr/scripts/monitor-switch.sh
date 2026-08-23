#!/usr/bin/env bash

# Persist the last monitor-derived mode so switching is edge-triggered on real
# plug/unplug events. A mode that arrives via an incoming push runs switch-*
# directly (not this script), so it never touches this state and never bounces
# back to the peer.
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/theme-monitor-mode"

# Prints the monitor-derived mode: "light" when the DSC e-ink panel is
# present, else "dark". This is Layer A only (this machine's own desktop
# appearance) — session colours travel separately via THEME_MODE (see
# theming.nix), which this poll loop never touches.
current_mode() {
  # Monitor presence is the automatic theme trigger. The DSC e-ink display
  # selects light mode; its absence selects dark mode.
  if hyprctl monitors | grep -q "DSC"; then
    echo light
  else
    echo dark
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
# live Hyprland/wallpaper state and seed the state file.
mode=$(current_mode)
apply_mode "$mode"
mkdir -p "$(dirname "$STATE_FILE")"
printf '%s\n' "$mode" > "$STATE_FILE"

# Launch terminal at boot if in Dark Mode (no DSC monitor), but only on the
# home role: the remote role already gets its own startup terminal via
# role.lua's startup hook, so this would otherwise double up on it.
# shellcheck source=/dev/null
. "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/role.env" 2>/dev/null || true
if [ "$mode" = "dark" ] && [ "${HYPR_ROLE:-}" != "remote" ]; then
  kitty --class kitty-main tmux new-session -A -s main &
fi

# Poll state so this script has no socat runtime dependency. Apply the theme
# scripts directly. Only a change relative to the stored mode is a real edge:
# on such an edge, record it and apply locally. Monitor edges no longer push to the peer — the only
# remaining theme-push caller is theme-toggle (see theming.nix), a deliberate
# manual action, not this automatic poll.
while sleep 2; do
  desired=$(current_mode)

  stored=$(cat "$STATE_FILE" 2>/dev/null || true)
  # ${stored%% *} keeps only the first word. A state file left over from
  # before this format dropped its second ("source") word — e.g. a stale
  # "light monitor" — still parses correctly as just "light".
  stored=${stored%% *}

  if [ "$desired" != "$stored" ]; then
    printf '%s\n' "$desired" > "$STATE_FILE"
    apply_mode "$desired"
  fi
done
