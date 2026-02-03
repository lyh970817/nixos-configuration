{ config, pkgs, lib, ... }:

{
  # Enable zsh system-wide (required when user shell is zsh)
  programs.zsh.enable = true;

  # User account definition
  users.users.andongni = {
    isNormalUser = true;
    description = "andongni";
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.zsh;
  };

  # Allow passwordless sudo for andongni to run system activation
  security.sudo.extraRules = [
    {
      users = [ "andongni" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
