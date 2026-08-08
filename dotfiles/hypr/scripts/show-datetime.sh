#!/usr/bin/env bash

# Named time zones live here on NixOS rather than under /usr/share.
export TZDIR=/etc/zoneinfo

now=$(date +%s)

system_date=$(date -d "@${now}" "+%Y-%m-%d (%A)")
system_day=$(date -d "@${now}" "+%F")

beijing_time=$(TZ=Asia/Shanghai date -d "@${now}" "+%H:%M")

uk_day=$(TZ=Europe/London date -d "@${now}" "+%F")
uk_time=$(TZ=Europe/London date -d "@${now}" "+%H:%M")

uk_day_note=""
if [[ "$uk_day" < "$system_day" ]]; then
  uk_day_note=" -1d"
fi

# Send notification
notify-send \
  "${beijing_time} | ${uk_time}${uk_day_note}" \
  "${system_date}" \
  --urgency=normal
