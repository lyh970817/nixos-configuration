{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Greetd display manager
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "start-hyprland";
      user = "andongni";
    };
  };

  # Enable automatic login
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "andongni";
}
