{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable zsh system-wide (required when user shell is zsh)
  programs.zsh.enable = true;

  # User account definition
  users.users.andongni = {
    isNormalUser = true;
    description = "andongni";
    extraGroups = [
      "networkmanager"
      "wheel"
      "docker"
    ];
    shell = pkgs.zsh;
  };

  # Enable passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;
}
