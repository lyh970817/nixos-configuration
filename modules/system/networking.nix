{ config, pkgs, lib, ... }:

{
  # Hostname
  networking.hostName = "andongni";

  # Enable networking
  networking.networkmanager.enable = true;
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
            ${pkgs.systemd}/bin/systemctl --user start captive-browser-auto.service \
          || ${pkgs.util-linux}/bin/logger -t captive-browser "Failed to start captive-browser-auto.service."
      '';
    }
  ];

  programs.captive-browser = {
    enable = true;
    interface = "wlp1s0";
  };

  systemd.user.services.captive-browser-auto = {
    description = "Open captive portal browser";
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "exec";
      ExecStart = "/run/current-system/sw/bin/captive-browser";
    };
  };

  # Firewall configuration
  networking.firewall.allowedTCPPorts = [ 9090 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.trustedInterfaces = [ "utun" ];
  networking.firewall.checkReversePath = false;
}
