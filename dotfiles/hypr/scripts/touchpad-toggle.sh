#!/usr/bin/env bash

# Touchpad device names change across firmware/driver revisions (and differ
# between hosts), so discover them at runtime instead of hardcoding one.
# Hyprland's Lua config keeps the current state in its own Lua VM, where a
# config reload resets it together with the actual device configuration.

mapfile -t touchpads < <(hyprctl -j devices | grep -o '"name": *"[^"]*touchpad[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/')

if [ "${#touchpads[@]}" -eq 0 ]; then
  if command -v notify-send > /dev/null; then
    notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "No touchpad device found"
  fi
  exit 1
fi

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

if [ "$current" = true ]; then
  target=false
  label="disabled"
else
  target=true
  label="enabled"
fi

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

if command -v notify-send > /dev/null; then
  notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "Touchpad $label"
fi
