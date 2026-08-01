{ pkgs, ... }:

let
  dayTemperature = 6500;
  # 2000 K is deliberately very warm for the night setting.
  nightTemperature = 2000;

  hyprsunsetToggle = pkgs.writeShellApplication {
    name = "hyprsunset-toggle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.systemd
    ];
    text = ''
      wait_for_socket() {
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          if hyprctl hyprsunset temperature ${toString nightTemperature} >/dev/null 2>&1; then
            return 0
          fi
          sleep 0.1
        done

        printf '%s\n' "hyprsunset IPC socket did not become ready" >&2
        return 1
      }

      if systemctl --user is-active --quiet hyprsunset.service; then
        current_temperature=$(hyprctl hyprsunset temperature)
        if [ "$current_temperature" = "${toString nightTemperature}" ]; then
          systemctl --user stop hyprsunset.service
        else
          hyprctl hyprsunset temperature ${toString nightTemperature}
        fi
      else
        systemctl --user start hyprsunset.service
        wait_for_socket
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
          temperature = dayTemperature;
        }
        {
          time = "16:00";
          temperature = nightTemperature;
        }
      ];
    };
  };

  home.packages = [ hyprsunsetToggle ];
}
