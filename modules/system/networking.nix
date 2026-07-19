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
in
{
  # Hostname comes only from the generated /etc/nixos/local.nix (out-of-tree).

  # Enable networking
  networking.networkmanager.enable = true;
  services.tailscale.enable = true;
  # Declarative best-effort hook for Tailscale SSH: this only takes effect
  # when a `tailscale up` invocation uses an auth key (e.g. non-interactive
  # provisioning). The primary way SSH gets enabled is the manual first-boot
  # `tailscale up --ssh` the user runs on the home machine.
  services.tailscale.extraUpFlags = lib.mkIf (config.portable.role == "home") [ "--ssh" ];
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
  # "utun" is the mihomo TUN device; "tailscale0" is added so mosh's UDP and
  # Tailscale SSH flow freely over the tailnet without opening ports publicly.
  networking.firewall.trustedInterfaces = [
    "utun"
    "tailscale0"
  ];
  networking.firewall.checkReversePath = false;
}
