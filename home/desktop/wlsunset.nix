{ lib, osConfig, pkgs, ... }:

let
  wlsunsetToggle = pkgs.writeShellApplication {
    name = "wlsunset-toggle";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if systemctl --user is-active --quiet wlsunset.service; then
        systemctl --user stop wlsunset.service
      else
        systemctl --user start wlsunset.service
      fi
    '';
  };
in
{
  # Keep the Paperlike output unchanged on the remote laptop; the home desktop
  # has no fixed internal output, so it follows all connected displays.
  services.wlsunset = {
    enable = true;
    output = if osConfig.portable.role == "remote" then "eDP-1" else null;

    sunrise = "06:00";
    sunset = "16:00";
    temperature = {
      day = 6500;
      night = 4000;
    };
  };

  home.packages = [ wlsunsetToggle ];
}
