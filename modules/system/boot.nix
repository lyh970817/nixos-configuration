{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Early KMS for AMD GPU to fix intermittent "HDMI not connected" issues
  boot.initrd.kernelModules = [ "amdgpu" ];
}
