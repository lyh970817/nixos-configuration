{
  # Stop systemd-logind from suspending on lid close, on all hosts. The laptop
  # wants the lid to only trigger a DPMS-off via Hyprland (see
  # the role fragment in home/programs/dotfiles.nix); the home desktop's
  # firmware exposes a buggy
  # phantom ACPI lid device (LID0) whose spurious "closed" events would
  # otherwise suspend it.
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
}
