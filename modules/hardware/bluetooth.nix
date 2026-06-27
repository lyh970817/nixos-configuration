{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable Blueman for graphical Bluetooth management
  services.blueman.enable = true;
}
