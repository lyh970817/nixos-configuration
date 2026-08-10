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

# The state file holds the current enabled state (1 = enabled). A missing file
# means the touchpad is at its config default, which is disabled, so the first
# press enables it.
if [ "$(cat "$state" 2> /dev/null)" = "1" ]; then
  target=false
  label="disabled"
else
  target=true
  label="enabled"
fi

# `hyprctl keyword` is refused under the Lua config manager ("keyword can't
# work with non-legacy parsers. Use eval."), so re-declare the device with
# `hl.device` through `hyprctl eval`. Device names come from hyprctl's JSON and
# can contain quotes/backslashes in principle, so escape them for a Lua literal.
for dev in "${touchpads[@]}"; do
  escaped="${dev//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  hyprctl eval "hl.device({ name = \"$escaped\", enabled = $target })"
done

printf '%s\n' "$([ "$target" = true ] && echo 1 || echo 0)" > "$state"

if command -v notify-send > /dev/null; then
  notify-send -h string:x-canonical-private-synchronous:touchpad-toggle "Touchpad" "Touchpad $label"
fi
