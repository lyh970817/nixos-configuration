# Mako Notification Daemon Configuration
# Managed by home-manager
# Original: ~/.config/mako/config
# Theme switching handled by darkman hooks via makoctl mode
{ config, pkgs, ... }:

{
  services.mako = {
    enable = true;
    settings = {
      font = "Hack Nerd Font 12";
      background-color = "#ffffff";
      text-color = "#000000";
      width = 450;
      height = 400;
      margin = "10";
      padding = "10";
      border-size = 2;
      border-color = "#000000";
      border-radius = 4;
      icons = true;
      max-icon-size = 64;
      anchor = "top-right";
      default-timeout = 10000;
      layer = "overlay";
      max-visible = 5;
      format = "<b>%s</b>\\n%b";
    };

    extraConfig = ''
      [urgency=critical]
      background-color=#000000
      text-color=#ffffff
      border-color=#000000

      [mode=dark]
      # Matrix Green Theme (10% Dimmer Colors)
      font=Hack Nerd Font 12
      background-color=#000000
      text-color=#4AB34D
      width=450
      height=400
      margin=10
      padding=10
      border-size=2
      border-color=#4AB34D
      border-radius=4
      icons=1
      max-icon-size=64
      anchor=top-right
      default-timeout=10000
      layer=overlay
      max-visible=5
      format=<b>%s</b>\n%b

      # Low urgency notifications - darker green
      [urgency=low mode=dark]
      background-color=#000000
      text-color=#2E9031
      border-color=#207F23

      # Normal urgency (default values above apply)
      [urgency=normal mode=dark]
      background-color=#000000
      text-color=#4AB34D
      border-color=#4AB34D

      # Critical urgency - inverted with bright green
      [urgency=critical mode=dark]
      background-color=#4AB34D
      text-color=#000000
      border-color=#4AB34D
      default-timeout=0
    '';
  };
}
