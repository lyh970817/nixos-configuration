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
      # Compact VT220-inspired operator-console treatment.
      font=Hack Nerd Font 12
      background-color=#080705
      text-color=#D99B32
      width=400
      height=400
      margin=10
      padding=8
      border-size=1
      border-color=#BE842A
      border-radius=0
      icons=0
      anchor=top-right
      default-timeout=10000
      layer=overlay
      max-visible=5
      format=[%a] <b>%s</b>\n%b

      # Low urgency notifications - darker amber
      [urgency=low mode=dark]
      background-color=#080705
      text-color=#9B6D24
      border-color=#6E501D

      # Normal urgency (default values above apply)
      [urgency=normal mode=dark]
      background-color=#080705
      text-color=#D99B32
      border-color=#D99B32

      # Critical urgency - inverted with bright amber
      [urgency=critical mode=dark]
      background-color=#D99B32
      text-color=#080705
      border-color=#D99B32
      default-timeout=0
    '';
  };
}
