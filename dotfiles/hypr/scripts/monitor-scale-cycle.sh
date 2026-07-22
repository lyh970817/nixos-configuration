#!/usr/bin/env bash

# Fn+Space (XF86ZoomReset) cycles the focused monitor's scale. Monitor names
# and valid scales differ across hosts, so discover the focused monitor and its
# current scale at runtime rather than hardcoding. Hyprland rounds a scale that
# would give fractional logical pixels and reports the rounded value; treat a
# candidate whose applied scale doesn't match as rejected and skip to the next.
set -euo pipefail

scales=(1.0 1.25 1.5)

notify() {
  command -v notify-send > /dev/null &&
    notify-send -h string:x-canonical-private-synchronous:monitor-scale \
      "Display scale" "$1"
}

# Prefer the focused monitor; fall back to the first one.
mon="$(hyprctl monitors -j | jq -r 'first(.[] | select(.focused)) // .[0]')"
name="$(printf '%s' "$mon" | jq -r '.name')"
cur="$(printf '%s' "$mon" | jq -r '.scale')"

if [ -z "$name" ] || [ "$name" = "null" ]; then
  notify "no monitor found"
  exit 1
fi

# Index of the current scale within the candidate list (approx match), or -1.
idx=-1
for i in "${!scales[@]}"; do
  if awk -v a="$cur" -v b="${scales[$i]}" 'BEGIN { exit !(a > b - 0.01 && a < b + 0.01) }'; then
    idx="$i"
  fi
done

n="${#scales[@]}"
for step in $(seq 1 "$n"); do
  cand="${scales[$(((idx + step) % n))]}"
  hyprctl keyword monitor "$name,preferred,auto,$cand" > /dev/null 2>&1 || true
  sleep 0.2
  applied="$(hyprctl monitors -j | jq -r --arg n "$name" 'first(.[] | select(.name == $n)) | .scale')"
  if awk -v a="$applied" -v b="$cand" 'BEGIN { exit !(a > b - 0.01 && a < b + 0.01) }'; then
    notify "$name  ×$cand"
    exit 0
  fi
done

notify "scale unchanged"
exit 1
