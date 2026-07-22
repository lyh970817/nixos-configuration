#!/usr/bin/env bash

# Fn+Z (XF86KbdLightOnOff) cycles the keyboard backlight. This is a "type 2"
# Toshiba backlight: the toshiba_acpi_dnbk driver's kbd_backlight LED only
# flips an illumination bit that the SCI *mode* overrides, so real control is
# the kbd_backlight_mode attribute (auto=2, on=8, off=16). A NixOS udev/service
# rule makes that attribute group-writable; cycle Auto -> On -> Off.
set -euo pipefail

attr=/sys/bus/acpi/devices/DNBK0001:00/kbd_backlight_mode

notify() {
  command -v notify-send > /dev/null &&
    notify-send -h string:x-canonical-private-synchronous:kbd-backlight \
      "Keyboard backlight" "$1"
}

if [ ! -w "$attr" ]; then
  notify "control unavailable"
  exit 1
fi

case "$(cat "$attr")" in
  2) next=8 label="On" ;;   # auto -> on
  8) next=16 label="Off" ;; # on   -> off
  *) next=2 label="Auto" ;; # off  -> auto
esac

printf '%s\n' "$next" > "$attr"
notify "$label"
