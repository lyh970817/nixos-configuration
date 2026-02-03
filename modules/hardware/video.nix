{ config, pkgs, lib, ... }:

{
  # Load AMD driver for Xorg and Wayland
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Enable graphics acceleration
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
