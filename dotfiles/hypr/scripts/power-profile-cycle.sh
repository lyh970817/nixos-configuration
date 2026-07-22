#!/usr/bin/env bash

# Fn+F2 (XF86Battery) cycles power-profiles-daemon profiles. The X30W-K uses
# intel_pstate EPP (no /sys/firmware/acpi/platform_profile), so ppd offers
# power-saver/balanced/performance via the EPP driver. Cycle low -> high over
# only the profiles ppd actually advertises on this machine.
set -euo pipefail

if ! command -v powerprofilesctl > /dev/null; then
  command -v notify-send > /dev/null &&
    notify-send -h string:x-canonical-private-synchronous:power-profile \
      "Power profile" "powerprofilesctl not available"
  exit 1
fi

order=(power-saver balanced performance)
current="$(powerprofilesctl get 2> /dev/null || true)"
mapfile -t avail < <(powerprofilesctl list 2> /dev/null | grep -oE '^[* ] [a-z-]+:' | grep -oE '[a-z-]+')

cycle=()
for p in "${order[@]}"; do
  for a in "${avail[@]}"; do
    [ "$p" = "$a" ] && cycle+=("$p")
  done
done
[ "${#cycle[@]}" -eq 0 ] && cycle=(balanced)

idx=0
for i in "${!cycle[@]}"; do
  [ "${cycle[$i]}" = "$current" ] && idx="$i"
done
next="${cycle[$(((idx + 1) % ${#cycle[@]}))]}"

powerprofilesctl set "$next"

if command -v notify-send > /dev/null; then
  notify-send -h string:x-canonical-private-synchronous:power-profile \
    "Power profile" "$next"
fi
