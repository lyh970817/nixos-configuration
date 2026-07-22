#!/usr/bin/env bash

# Touchpad device names change across firmware/driver revisions (and differ
# between hosts), so discover them at runtime instead of hardcoding one.
# hyprctl reports no enabled state for a device, so track it ourselves.
state="${XDG_RUNTIME_DIR:-/tmp}/hypr-touchpad-enabled"

mapfile -t touchpads < <(hyprctl -j devices | grep -o '"name": *"[^"]*touchpad[^"]*"' | sed -E 's/.*"([^"]*)"$/\1/')

if [ "${#touchpads[@]}" -eq 0 ]; then
  if command -v notify-send > /dev/null; then
    notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "No touchpad device found"
  fi
  exit 1
fi

if [ "$(cat "$state" 2> /dev/null)" = "0" ]; then
  target=true
  label="enabled"
else
  target=false
  label="disabled"
fi

for dev in "${touchpads[@]}"; do
  hyprctl keyword "device[$dev]:enabled" "$target"
done

printf '%s\n' "$([ "$target" = true ] && echo 1 || echo 0)" > "$state"

if command -v notify-send > /dev/null; then
  notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "Touchpad $label"
fi
