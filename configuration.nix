# NixOS Configuration
# Modular configuration with Flakes and Home Manager
{ config, pkgs, lib, ... }:

{
  imports = [
    # Hardware configuration
    ./hardware-configuration.nix

    # System modules
    ./modules/system/nix.nix
    ./modules/system/boot.nix
    ./modules/system/networking.nix
    ./modules/system/locale.nix

    # Desktop environment
    ./modules/desktop/hyprland.nix
    ./modules/desktop/xdg-portal.nix

    # Hardware support
    ./modules/hardware/audio.nix
    ./modules/hardware/bluetooth.nix
    ./modules/hardware/printing.nix
    ./modules/hardware/video.nix

    # System services
    ./modules/services/greetd.nix
    ./modules/services/yandex-disk.nix
    ./modules/services/mihomo.nix
    ./modules/services/keyd.nix

    # Programs
    ./modules/programs/input-method.nix
    ./modules/programs/firefox.nix
    ./modules/programs/development.nix

    # User accounts
    ./users/andongni.nix
  ];

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Enable firmware
  hardware.enableRedistributableFirmware = true;

  services.envfs.enable = true;

  # Docker
  virtualisation.docker.enable = true;

  fonts.packages = with pkgs; [
    wqy_microhei
    wqy_zenhei
  ];

  # System-level font directory (required for some applications)
  fonts.fontDir.enable = true;

  # NixOS version
  system.stateVersion = "25.05";
}
