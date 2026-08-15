{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Bootloader
  boot.loader.systemd-boot.enable = true;
  # Backstop against /boot filling with kernels; the 14d GC in
  # modules/system/nix.nix does the real work.
  boot.loader.systemd-boot.configurationLimit = 20;
  boot.loader.efi.canTouchEfiVariables = true;
}
