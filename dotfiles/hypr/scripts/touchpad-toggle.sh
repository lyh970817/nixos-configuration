#!/usr/bin/env bash

# Touchpad device names change across firmware/driver revisions (and differ
# between hosts), so discover them at runtime instead of hardcoding one.
# Hyprland's Lua config keeps the current state in its own Lua VM, where a
# config reload resets it together with the actual device configuration. The
# transitional legacy manager cannot expose per-device values through IPC, so
# its config synchronizes this fallback file on every reload.
state="${XDG_RUNTIME_DIR:-/tmp}/hypr-touchpad-enabled"

mapfile -t touchpads < <(hyprctl -j devices | grep -o '"name": *"[^"]*touchpad[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/')

if [ "${#touchpads[@]}" -eq 0 ]; then
  if command -v notify-send > /dev/null; then
    notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "No touchpad device found"
  fi
  exit 1
fi

manager="$(hypr-ipc manager)"
if [ "$manager" = "lua" ]; then
  current="$(hyprctl repl 'return touchpad_enabled' 2> /dev/null)"
  case "$current" in
  true | false) ;;
  *)
    if command -v notify-send > /dev/null; then
      notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "Unable to read touchpad state"
    fi
    exit 1
    ;;
  esac
else
  current=false
  [ "$(cat "$state" 2> /dev/null)" = "1" ] && current=true
fi

if [ "$current" = true ]; then
  target=false
  label="disabled"
else
  target=true
  label="enabled"
fi

if [ "$manager" = "lua" ]; then
  # Apply every device and update the queried state in one compositor request.
  # Device names come from Hyprland's JSON, so escape them for Lua literals.
  expression=""
  for dev in "${touchpads[@]}"; do
    escaped="${dev//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    expression+="hl.device({ name = \"$escaped\", enabled = $target }); "
  done
  expression+="touchpad_enabled = $target"
  reply="$(hyprctl eval "$expression" 2>&1)"
  [ "$reply" = "ok" ] || exit 1
else
  # TRANSITIONAL: the legacy manager has no per-device state query. Its config
  # resets this file to 1 whenever it reloads the enabled default.
  for dev in "${touchpads[@]}"; do
    reply="$(hyprctl keyword "device[$dev]:enabled" "$target" 2>&1)"
    [ "$reply" = "ok" ] || exit 1
  done
  if [ "$target" = true ]; then
    printf '1\n' > "$state"
  else
    printf '0\n' > "$state"
  fi
fi

if command -v notify-send > /dev/null; then
  notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "Touchpad $label"
fi
