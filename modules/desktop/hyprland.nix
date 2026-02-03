{ config, pkgs, lib, ... }:

{
  # X11 configuration
  services.xserver.enable = false;
  services.xserver.xkb.options = "caps:escape";

  # Seatd for seat management
  services.seatd.enable = true;

  # Hyprland configuration
  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  # Environment variables for Wayland/Hyprland
  environment.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    # Force Electron and Chromium apps to use native Wayland
    NIXOS_OZONE_WL = "1";
    WLR_NO_HARDWARE_CURSORS = "1";
    XDG_SESSION_TYPE = "wayland";
    XDG_CURRENT_DESKTOP = "Hyprland";
    XDG_SESSION_DESKTOP = "Hyprland";
    XDG_DATA_DIRS = lib.mkAfter [
      "$HOME/.local/share"
      "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
    ];
    XMODIFIERS = "@im=fcitx";
    GLFW_IM_MODULE = "fcitx";
  };
}
