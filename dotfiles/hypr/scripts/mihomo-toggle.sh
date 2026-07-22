#!/usr/bin/env bash

# Fn+F8 (XF86WLAN) toggles the mihomo proxy service. The physical WLAN key
# exists only on the laptop, so this shared bind is inert on the desktop.
# systemctl start/stop of the system unit is authorized for the local wheel
# session by a scoped polkit rule (see modules/services/mihomo.nix), so no sudo
# is needed. NOTE: stopping mihomo drops this machine's proxy (and any model
# connection routed through it).
set -euo pipefail

notify() {
  command -v notify-send > /dev/null &&
    notify-send -h string:x-canonical-private-synchronous:mihomo \
      "Proxy (mihomo)" "$1"
}

if systemctl is-active --quiet mihomo; then
  if systemctl stop mihomo; then notify "stopped"; else notify "stop failed"; fi
else
  if systemctl start mihomo; then notify "started"; else notify "start failed"; fi
fi
