# Mako Notification Daemon Configuration
# Managed by home-manager
# Original: ~/.config/mako/config
# Theme switching handled by darkman hooks via makoctl mode
{ config, pkgs, ... }:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;
in

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
      background-color=#${p.background}
      text-color=#${p.foreground}
      width=400
      height=400
      margin=10
      padding=8
      border-size=1
      border-color=#${p.accent}
      border-radius=0
      icons=0
      anchor=top-right
      default-timeout=10000
      layer=overlay
      max-visible=5
      format=<b>%s</b>\n%b

      # Low urgency notifications - darker amber
      [urgency=low mode=dark]
      background-color=#${p.background}
      text-color=#${p.secondaryText}
      border-color=#${p.mutedText}

      # Normal urgency (default values above apply)
      [urgency=normal mode=dark]
      background-color=#${p.background}
      text-color=#${p.foreground}
      border-color=#${p.foreground}

      # Critical urgency - inverted with bright amber
      [urgency=critical mode=dark]
      background-color=#${p.foreground}
      text-color=#${p.background}
      border-color=#${p.foreground}
      default-timeout=0
    '';
  };
}
