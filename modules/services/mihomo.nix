{ config, pkgs, lib, ... }:

{
  # Mihomo (Clash Meta) proxy service
  services.mihomo = {
    enable = true;
    tunMode = true;
    webui = pkgs.metacubexd;
    configFile = /. + "/home/andongni/Yandex.Disk/System/nixos-configuration/mihomo-config.yaml";
  };
}
