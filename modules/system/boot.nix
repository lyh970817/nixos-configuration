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
  # Any key in that second stops the countdown.
  boot.loader.timeout = 1;

  # Keep KERN_ERR off the text consoles; the journal still records it. The
  # laptop's EC fires a harmless `_Q01.CHRG AE_NOT_FOUND` ACPI error every few
  # seconds while charging, which otherwise floods any tty.
  boot.consoleLogLevel = 3;
}
