#!/usr/bin/env bash

# Persist the last monitor-derived mode so switching is edge-triggered on real
# plug/unplug events. A mode that arrives via an incoming push runs switch-*
# directly (not this script), so it never touches this state and never bounces
# back to the peer.
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/theme-monitor-mode"

# SSH/mosh theme override: theme-hold (see theming.nix), exec'd by the
# client's ssh/mosh wrapper (shell.nix) or home-terminal (dotfiles.nix),
# registers the wrapped session process's PID here to hand its theme off to
# this host for the session's duration.
OVERRIDE_DIR="/run/user/$(id -u)/theme-ssh-override"

# Prints "<mode> <source>". source is "override" while an SSH session has
# handed its theme to us, else "monitor" (the fallback automatic trigger).
current_mode() {
  if [ -d "$OVERRIDE_DIR" ]; then
    live=0
    for pidfile in "$OVERRIDE_DIR"/pids/*; do
      [ -e "$pidfile" ] || continue
      pid=$(basename "$pidfile")
      if kill -0 "$pid" 2>/dev/null; then
        live=1
      else
        rm -f "$pidfile"
      fi
    done
    if [ "$live" -eq 1 ]; then
      override_mode=$(cat "$OVERRIDE_DIR/mode" 2>/dev/null)
      case "$override_mode" in
      dark | light)
        echo "$override_mode override"
        return
        ;;
      esac
      # Mode file missing/empty/torn (mid-write race): fall through below
      # rather than apply_mode-ing garbage.
    fi
    # No registered process survived: the override has expired. Leave the
    # (now-empty) dir in place rather than rm -rf it here: theme-hold's
    # registration is non-atomic (mkdir, then echo mode, then touch pid), so
    # a poll tick landing mid-registration could otherwise delete the dir out
    # from under a session that's still starting up. A lingering dir on
    # tmpfs is harmless; only live registered PIDs gate the override, and the
    # next registration just reuses/overwrites its contents.
  fi

  # Monitor presence is the automatic theme trigger. The DSC e-ink display
  # selects light mode; its absence selects dark mode. This setup does not
  # use Darkman's time, location, or GeoClue transition mechanisms.
  if hyprctl monitors | grep -q "DSC"; then
    echo "light monitor"
  else
    echo "dark monitor"
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
mode_source=$(current_mode)
mode=${mode_source%% *}
apply_mode "$mode"
mkdir -p "$(dirname "$STATE_FILE")"
printf '%s\n' "$mode_source" > "$STATE_FILE"

# Launch terminal at boot if in Dark Mode (no DSC monitor), but only on the
# home role: the remote role already gets its own startup terminal via
# role.conf's exec-once, so this would otherwise double up on it.
# shellcheck source=/dev/null
. "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/role.env" 2>/dev/null || true
if [ "$mode" = "dark" ] && [ "${HYPR_ROLE:-}" != "remote" ]; then
  alacritty --class Alacritty-main --command tmux new-session -A -s main &
fi

# Poll state so this script has no socat runtime dependency. Apply the theme
# scripts directly rather than asking Darkman to schedule a transition. Only a
# change relative to the stored mode is a real edge: on such an edge, record
# it and apply locally. Only push to the peer when both the old and new
# state are "monitor": an override transition originates from (or reverts
# around) the peer's own session, so pushing it back would bounce the peer's
# theme right back at it.
while sleep 2; do
  desired_full=$(current_mode)
  desired=${desired_full%% *}
  desired_source=${desired_full#* }

  stored_full=$(cat "$STATE_FILE" 2>/dev/null || true)
  stored=${stored_full%% *}
  case "$stored_full" in
  *' '*) stored_source=${stored_full#* } ;;
  *) stored_source=monitor ;; # legacy single-word state file
  esac

  if [ "$desired" != "$stored" ]; then
    printf '%s\n' "$desired_full" > "$STATE_FILE"
    apply_mode "$desired"
    if [ "$stored_source" = "monitor" ] && [ "$desired_source" = "monitor" ]; then
      theme-push "$desired"
    fi
  fi
done
