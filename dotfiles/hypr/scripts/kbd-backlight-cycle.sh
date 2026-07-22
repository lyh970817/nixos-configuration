#!/usr/bin/env bash

# Fn+Z (XF86KbdLightOnOff) cycles the keyboard backlight. This is a "type 2"
# Toshiba backlight: the toshiba_acpi_dnbk driver's kbd_backlight LED only
# flips an illumination bit that the SCI *mode* overrides, so real control is
# the kbd_backlight_mode attribute (auto=2, on=8, off=16). The driver recreates
# that attribute root-owned on every mode change (sysfs_update_group), so it
# can't be made group-writable; write it via passwordless sudo instead (this
# host runs wheel without a sudo password).
set -euo pipefail

attr=/sys/bus/acpi/devices/DNBK0001:00/kbd_backlight_mode

notify() {
  command -v notify-send > /dev/null &&
    notify-send -h string:x-canonical-private-synchronous:kbd-backlight \
      "Keyboard backlight" "$1"
}

if [ ! -r "$attr" ]; then
  notify "control unavailable"
  exit 1
fi

case "$(cat "$attr")" in
  2) next=8 label="On" ;;   # auto -> on
  8) next=16 label="Off" ;; # on   -> off
  *) next=2 label="Auto" ;; # off  -> auto
esac

if printf '%s\n' "$next" | sudo -n tee "$attr" > /dev/null 2>&1; then
  notify "$label"
else
  notify "control unavailable"
  exit 1
fi
