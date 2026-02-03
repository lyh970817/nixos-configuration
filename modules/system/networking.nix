{ config, pkgs, lib, ... }:

{
  # Hostname
  networking.hostName = "andongni";

  # Enable networking
  networking.networkmanager.enable = true;

  # Firewall configuration
  networking.firewall.allowedTCPPorts = [ 9090 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.trustedInterfaces = [ "utun" ];
  networking.firewall.checkReversePath = false;
}
