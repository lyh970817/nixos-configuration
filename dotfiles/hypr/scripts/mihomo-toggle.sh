#!/usr/bin/env bash

# Fn+F8 (XF86WLAN) toggles the mihomo proxy service. The physical WLAN key
# exists only on the laptop, so this shared bind is inert on the desktop.
# start/stop go through passwordless sudo (this host runs wheel without a sudo
# password, same as kbd-backlight-cycle.sh). NOTE: stopping mihomo drops this
# machine's proxy, including the model connection routed through it.
set -euo pipefail

notify() {
  command -v notify-send > /dev/null &&
    notify-send -h string:x-canonical-private-synchronous:mihomo \
      "Proxy (mihomo)" "$1"
}

if systemctl is-active --quiet mihomo; then
  if sudo -n systemctl stop mihomo; then notify "stopped"; else notify "stop failed"; fi
else
  if sudo -n systemctl start mihomo; then notify "started"; else notify "start failed"; fi
fi
