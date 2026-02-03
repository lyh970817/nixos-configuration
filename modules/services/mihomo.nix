{ config, pkgs, lib, ... }:

{
  # Mihomo (Clash Meta) proxy service
  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = /. + "/home/andongni/nixos-configuration/clash-meta-config.yaml";
  };
}
