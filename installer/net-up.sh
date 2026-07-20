#!/usr/bin/env bash
# installer/net-up.sh
#
# Brings the installer online through the user's own proxy so `nixos-install`
# can fetch the handful of target-specific paths (e.g. the laptop's own initrd)
# that the baked ISO closure cannot contain. The target is Wi-Fi only and sits
# behind the GFW, so:
#
#   1. connect Wi-Fi interactively (nmtui),
#   2. run mihomo with the baked config (TUN stripped -- we only need the
#      127.0.0.1:7890 mixed-port, not a routing hijack), replaying the user's
#      normal tunnel,
#   3. wait until proxied egress actually works,
#   4. point the nix-daemon at the proxy (a drop-in -- the daemon does the
#      downloads and does NOT inherit a caller's http_proxy env), and
#   5. write the proxy env to /run/installer-proxy-env for the login shell to
#      source so the nix *client* (flake eval fetches) is covered too.
#
# Best-effort: every failure path warns and returns 0 so the caller still runs
# install.sh. The baked closure covers the common case; the proxy is the safety
# net for the target-specific tail. Sourced/spawned from iso.nix's
# loginShellInit before install.sh.

set -uo pipefail

PROXY="http://127.0.0.1:7890"
MIHOMO_DIR="/run/mihomo"
CONFIG_SRC="/etc/nixos-secrets/mihomo-config.yaml"
CACHE_SRC="/etc/nixos-secrets/mihomo-cache"
ENV_FILE="/run/installer-proxy-env"

log() { printf '>> [net-up] %s\n' "$*" >&2; }

# Basic, GFW-safe reachability check (Baidu is always reachable in-country).
have_internet() { curl -sf -m 5 -o /dev/null https://www.baidu.com; }

# Does the proxy actually egress to a normally-blocked host?
proxy_works() { curl -x "$PROXY" -sf -m 8 -o /dev/null https://github.com; }

# ---------------------------------------------------------------------------
# 1. Wi-Fi
# ---------------------------------------------------------------------------
systemctl start NetworkManager 2>/dev/null || true

if have_internet; then
  log "network already reachable; skipping Wi-Fi setup"
else
  while true; do
    log "This machine needs Wi-Fi to reach your proxy. Launching nmtui..."
    log "Pick 'Activate a connection', choose your SSID, enter the password, then Back/Quit."
    sleep 2
    nmtui || true
    sleep 3
    if have_internet; then
      log "Wi-Fi is up."
      break
    fi
    printf '>> [net-up] Still no internet. Retry Wi-Fi? [Y/n] ' >&2
    read -r ans || ans=""
    case "$ans" in
      [nN]*)
        log "Continuing WITHOUT network -- install will rely only on the baked closure."
        exit 0
        ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# 2. mihomo (proxy only, no TUN)
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG_SRC" ]]; then
  log "no baked mihomo config at $CONFIG_SRC; continuing without proxy"
  exit 0
fi

log "Starting mihomo from the baked config (TUN disabled)..."
mkdir -p "$MIHOMO_DIR"
# Seed mihomo's data dir with this-machine's baked working state (resolved
# node list, cache.db with the selected node, rulesets, geoip db) so it boots
# from cached nodes and connects directly -- no startup fetch of the
# subscription/ruleset/geoip URLs, which may be unreachable on bare Wi-Fi.
if [[ -d "$CACHE_SRC" ]]; then
  cp -rf "$CACHE_SRC"/. "$MIHOMO_DIR"/ 2>/dev/null || true
fi
cp -f "$CONFIG_SRC" "$MIHOMO_DIR/config.yaml"
# Two tweaks for the installer's transient proxy:
#   - disable TUN: we only want the 127.0.0.1:7890 mixed-port, not a routing/
#     DNS hijack that would fight NetworkManager in the live installer;
#   - route the MATCH fallthrough (where nix's github/cache traffic lands)
#     through the `Auto` url-test group instead of the manually-selected
#     SSRDOG node, so the installer latency-tests every node and uses the
#     fastest. This affects ONLY this throwaway config; the installed system
#     keeps the user's normal selection from the baked config.
yq -i '.tun.enable = false | (.rules[] | select(. == "MATCH,SSRDOG")) = "MATCH,Auto"' \
  "$MIHOMO_DIR/config.yaml" 2>/dev/null || true

# Detached so it outlives this script; log kept for debugging on tty.
setsid mihomo -d "$MIHOMO_DIR" -f "$MIHOMO_DIR/config.yaml" \
  >"$MIHOMO_DIR/mihomo.log" 2>&1 &

log "Waiting for the proxy to come up (fetching subscription + health checks)..."
ready=""
for _ in $(seq 1 30); do
  if proxy_works; then
    ready=1
    break
  fi
  sleep 3
done

if [[ -z "$ready" ]]; then
  log "Proxy did not come up in time (see $MIHOMO_DIR/mihomo.log)."
  log "Continuing -- install will rely on the baked closure only."
  exit 0
fi
log "Proxy egress confirmed."

# ---------------------------------------------------------------------------
# 3. Point the nix-daemon at the proxy (it does the substitution downloads and
#    does NOT see this shell's http_proxy), then expose env for the nix client.
# ---------------------------------------------------------------------------
DROPIN_DIR="/run/systemd/system/nix-daemon.service.d"
mkdir -p "$DROPIN_DIR"
cat >"$DROPIN_DIR/proxy.conf" <<EOF
[Service]
Environment="https_proxy=$PROXY"
Environment="http_proxy=$PROXY"
Environment="all_proxy=$PROXY"
EOF
systemctl daemon-reload 2>/dev/null || true
systemctl restart nix-daemon 2>/dev/null || true
log "nix-daemon now routes through the proxy."

cat >"$ENV_FILE" <<EOF
export https_proxy=$PROXY
export http_proxy=$PROXY
export all_proxy=$PROXY
export HTTPS_PROXY=$PROXY
export HTTP_PROXY=$PROXY
export ALL_PROXY=$PROXY
EOF
log "Network ready. Proxy env written to $ENV_FILE."
exit 0
