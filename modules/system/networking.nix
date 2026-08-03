{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Runtime captive-browser. The interface is discovered per portal event, so the
  # tool is driven directly rather than through the NixOS module (which bakes the
  # interface in at build time and whose wrapper clobbers XDG_CONFIG_HOME).
  # captive-browser only reads $XDG_CONFIG_HOME/captive-browser.toml, so a
  # per-launch toml with the validated interface substituted is generated and
  # pointed at via XDG_CONFIG_HOME. The interface lands in bind-device (parsed
  # verbatim, not shell-expanded) and in the dhcp-dns command.
  captiveBrowserTomlTemplate = pkgs.writeText "captive-browser.toml.in" ''
    browser = """env XDG_CONFIG_HOME="@PREV_CONFIG_HOME@" ${pkgs.chromium}/bin/chromium --user-data-dir=''${XDG_DATA_HOME:-$HOME/.local/share}/chromium-captive --proxy-server="socks5://$PROXY" --host-resolver-rules="MAP * ~NOTFOUND , EXCLUDE localhost" --no-first-run --new-window --incognito -no-default-browser-check http://cache.nixos.org/"""
    dhcp-dns = """${pkgs.networkmanager}/bin/nmcli dev show @IFACE@ | ${pkgs.gnugrep}/bin/fgrep IP4.DNS"""
    socks5-addr = """localhost:1666"""
    bind-device = """@IFACE@"""
  '';

  captiveBrowserLauncher = pkgs.writeShellScript "captive-browser-launch" ''
    set -eu
    iface="''${1:?interface required}"
    prev_config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
    cfgdir="$(${pkgs.coreutils}/bin/mktemp -d)"
    trap '${pkgs.coreutils}/bin/rm -rf "$cfgdir"' EXIT
    ${pkgs.gnused}/bin/sed \
      -e "s|@IFACE@|$iface|g" \
      -e "s|@PREV_CONFIG_HOME@|$prev_config_home|g" \
      ${captiveBrowserTomlTemplate} > "$cfgdir/captive-browser.toml"
    export XDG_CONFIG_HOME="$cfgdir"
    ${pkgs.captive-browser}/bin/captive-browser
  '';

  # See the systemd unit below for the failure this repairs.
  reapStaleTailscaleSockets = pkgs.writeShellScript "tailscaled-reap-stale-sockets" ''
    set -euo pipefail

    pid="$(${pkgs.systemd}/bin/systemctl show -p MainPID --value tailscaled 2>/dev/null || true)"
    if [ -z "$pid" ] || [ "$pid" = 0 ]; then
      exit 0
    fi

    # Every address the kernel currently holds, on any interface.
    assigned="$(${pkgs.iproute2}/bin/ip -o addr show \
      | ${pkgs.gawk}/bin/awk '{print $4}' \
      | ${pkgs.coreutils}/bin/cut -d/ -f1 \
      | ${pkgs.coreutils}/bin/sort -u)"

    # Default `ss -t` reports connected sockets only, so listeners (which bind
    # wildcard addresses that would never match $assigned) are already excluded.
    sockets="$(${pkgs.iproute2}/bin/ss -tnHp | ${pkgs.gnugrep}/bin/grep -F "pid=$pid," || true)"
    if [ -z "$sockets" ]; then
      exit 0
    fi

    printf '%s\n' "$sockets" | while read -r _state _recvq _sendq local peer _rest; do
      # $local is "1.2.3.4:443" or "[2001:db8::1]:443".
      port="''${local##*:}"
      ip="''${local%:*}"
      family=-4
      src="$ip"
      case "$ip" in
        \[*\])
          ip="''${ip#[}"
          ip="''${ip%]}"
          family=-6
          src="[$ip]"
          ;;
      esac

      case "$ip" in
        "" | "*" | 0.0.0.0 | ::) continue ;;
      esac

      if printf '%s\n' "$assigned" | ${pkgs.gnugrep}/bin/grep -qxF "$ip"; then
        continue
      fi

      ${pkgs.util-linux}/bin/logger -t tailscaled-reaper \
        "Destroying tailscaled socket $local -> $peer (local address no longer assigned)."
      ${pkgs.iproute2}/bin/ss "$family" -K "src $src:$port" >/dev/null || true
    done

    exit 0
  '';
in
{
  # Hostname comes only from the generated /etc/nixos/local.nix (out-of-tree).

  # Enable networking
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;
  # Declarative best-effort hook for Tailscale SSH: this only takes effect
  # when a `tailscale up` invocation uses an auth key (e.g. non-interactive
  # provisioning). On an already-running node use `tailscale set --ssh=true`.
  #
  # Both roles accept inbound SSH now: home so the laptop can reach it, and
  # the laptop so home can push an image window back when Yazi opens a file
  # from inside a mosh session. This stays tailnet-only -- port 22 is never
  # added to allowedTCPPorts; "tailscale0" being a trusted interface below is
  # what lets it through, so nothing is reachable on the physical NIC.
  services.tailscale.extraUpFlags = [ "--ssh" ];
  # Tailscale DNS is left disabled so mihomo keeps ownership of resolv.conf
  # (its domain rules need to see queries). That costs the search domain
  # --accept-dns would normally install, so set it explicitly: bare peer names
  # then expand to MagicDNS FQDNs, which mihomo resolves via tailscaled's
  # resolver. Without this, bare names only work from static hosts entries.
  networking.search = [ "tail9abb26.ts.net" ];
  networking.networkmanager.settings = {
    connectivity = {
      enabled = true;
      uri = "http://www.msftconnecttest.com/connecttest.txt";
      interval = 60;
      timeout = 10;
      response = "Microsoft Connect Test";
    };
  };
  networking.networkmanager.dispatcherScripts = [
    {
      type = "basic";
      source = pkgs.writeShellScript "captive-browser-dispatcher" ''
        set -eu

        if [ "''${2:-}" != "connectivity-change" ]; then
          exit 0
        fi

        if [ "''${CONNECTIVITY_STATE:-}" != "PORTAL" ]; then
          exit 0
        fi

        iface="''${1:-}"
        if [ -z "$iface" ]; then
          ${pkgs.util-linux}/bin/logger -t captive-browser "Portal detected, but NetworkManager supplied no interface."
          exit 0
        fi

        # Only bind a real physical NM device; reject tailscale/virtual/loopback.
        iface_type="$(${pkgs.networkmanager}/bin/nmcli -t -f DEVICE,TYPE device | ${pkgs.gawk}/bin/awk -F: -v d="$iface" '$1 == d { print $2; exit }')"
        case "$iface_type" in
          wifi|ethernet) : ;;
          *)
            ${pkgs.util-linux}/bin/logger -t captive-browser "Refusing captive-browser on non-physical interface '$iface' (type ''${iface_type:-unknown})."
            exit 0
            ;;
        esac

        user="andongni"
        uid="$(${pkgs.coreutils}/bin/id -u "$user" 2>/dev/null || true)"
        if [ -z "$uid" ] || [ ! -S "/run/user/$uid/bus" ]; then
          ${pkgs.util-linux}/bin/logger -t captive-browser "Portal detected, but no active user session bus was found."
          exit 0
        fi

        ${pkgs.util-linux}/bin/runuser -u "$user" -- \
          ${pkgs.coreutils}/bin/env \
            XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            ${pkgs.systemd}/bin/systemctl --user start "captive-browser-auto@$iface.service" \
          || ${pkgs.util-linux}/bin/logger -t captive-browser "Failed to start captive-browser-auto@$iface.service."
      '';
    }
  ];

  # The NixOS captive-browser module is intentionally not enabled: on the pinned
  # nixpkgs it installs a setcap udhcpc wrapper affected by CVE-2026-25740, and
  # its wrapper cannot take a runtime interface. See
  # docs/captive-browser-cve-2026-25740.md. The tool is driven directly instead.
  # mosh is needed on both roles: the remote laptop dials `mosh home`, and the
  # home machine needs the mosh-server binary to answer.
  environment.systemPackages = [
    pkgs.captive-browser
    pkgs.mosh
  ];

  # tailscaled does not tear down its control connection when the kernel removes
  # the IPv6 address that connection is bound to, which is what happens whenever
  # the ISP delegates a new prefix: the old prefix's temporary (RFC 4941) address
  # is deleted outright while tailscaled keeps the socket. Every /machine/map
  # poll then hangs for its full 2-minute timeout, the coordination server marks
  # the node offline, and it never self-heals. Peer traffic keeps flowing over
  # WireGuard/UDP, so the only symptom is a node that reports "offline" while
  # SSH to it plainly works. Upstream tailscale/tailscale#1726, open since 2021.
  #
  # A socket bound to an address the kernel no longer has can never recover, so
  # destroying it is safe with no liveness check: tailscaled redials at once from
  # a current address. This stays narrower than restarting tailscaled, which
  # would drop live tailnet SSH sessions to repair a purely cosmetic-looking
  # fault. Deprecated-but-still-assigned addresses are deliberately left alone --
  # those are ordinary privacy-address rotation, where existing connections are
  # meant to drain gracefully.
  systemd.services.tailscaled-stale-socket-reaper = {
    description = "Destroy tailscaled sockets bound to removed local addresses";
    after = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = reapStaleTailscaleSockets;
    };
  };
  systemd.timers.tailscaled-stale-socket-reaper = {
    description = "Periodically reap stale tailscaled sockets";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
      AccuracySec = "10s";
    };
  };

  systemd.user.services."captive-browser-auto@" = {
    description = "Open captive portal browser on %i";
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "${captiveBrowserLauncher} %i";
    };
  };

  # Firewall configuration
  networking.firewall.allowedTCPPorts = [
    9090
    53
  ];
  networking.firewall.allowedUDPPorts = [ 53 ];
  # "Meta" is the mihomo TUN device (mihomo's built-in default name; the config
  # sets no tun.device override). "tailscale0" is added so mosh's UDP and
  # Tailscale SSH flow freely over the tailnet without opening ports publicly.
  networking.firewall.trustedInterfaces = [
    "Meta"
    "tailscale0"
  ];
  networking.firewall.checkReversePath = false;
}
