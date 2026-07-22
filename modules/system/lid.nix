{
  config,
  lib,
  ...
}:

{
  # Laptop-only: stop systemd-logind from suspending on lid close so the lid
  # only triggers a DPMS-off via Hyprland (see dotfiles/hypr/hyprland.conf).
  config = lib.mkIf (config.portable.role == "remote") {
    services.logind.lidSwitch = "ignore";
    services.logind.lidSwitchExternalPower = "ignore";
  };
}
