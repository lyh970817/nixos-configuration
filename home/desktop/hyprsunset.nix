{ pkgs, ... }:

let
  hyprsunsetToggle = pkgs.writeShellApplication {
    name = "hyprsunset-toggle";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if systemctl --user is-active --quiet hyprsunset.service; then
        systemctl --user stop hyprsunset.service
      else
        systemctl --user start hyprsunset.service
      fi
    '';
  };
in
{
  # wlsunset's wlr-gamma-control path fails on this Hyprland session. Use
  # Hyprsunset's native CTM protocol instead. Hyprsunset applies the profile
  # to every connected output because it has no per-output selector.
  services.hyprsunset = {
    enable = true;
    settings = {
      profile = [
        {
          time = "06:00";
          temperature = 6500;
        }
        {
          time = "16:00";
          temperature = 4000;
        }
      ];
    };
  };

  home.packages = [ hyprsunsetToggle ];
}
