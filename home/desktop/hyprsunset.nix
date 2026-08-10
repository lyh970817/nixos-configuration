{ pkgs, ... }:

let
  dayTemperature = 6500;
  dayGamma = 1.0;

  # Scheduled night warmth. Super+N toggles the service itself, applying its
  # own deliberately extreme override when it starts.
  #
  # Keep it a multiple of 100. matrixForKelvin does `temp /= 100` on an integer,
  # so the temperature is quantised to hundreds: 3500 and 3599 produce exactly
  # the same matrix, and 3480 would silently behave as 3400.
  nightTemperature = 3500;

  hyprsunsetWarmth = pkgs.writeShellApplication {
    name = "hyprsunset-warmth";
    runtimeInputs = [ pkgs.hyprland ];
    text = ''
      valid_temperature=false
      case "''${1-}" in
        *[!0-9]* | "") ;;
        *)
          if [ "$1" -ge 2000 ] && [ "$1" -le 6500 ] && [ $(( $1 % 100 )) -eq 0 ]; then
            valid_temperature=true
          fi
          ;;
      esac

      if [ "$#" -ne 1 ] || [ "$valid_temperature" != true ]; then
        printf '%s\n' "usage: hyprsunset-warmth TEMPERATURE_K (2000-6500, in 100 K steps)" >&2
        exit 2
      fi

      # hyprsunset accepts 1000-20000 K, but 2000-6500 K covers a conventional
      # night-light range through the configured daylight temperature. Its CTM
      # quantises temperatures to 100 K.
      hyprctl hyprsunset temperature "$1"
    '';
  };

  hyprsunsetNight = pkgs.writeShellApplication {
    name = "hyprsunset-night";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.systemd
    ];
    text = ''
      apply_night() {
        hyprctl hyprsunset gamma 100 >/dev/null 2>&1 &&
          hyprctl hyprsunset temperature 1500 >/dev/null 2>&1
      }

      wait_for_socket() {
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          if apply_night; then
            return 0
          fi
          sleep 0.1
        done

        printf '%s\n' "hyprsunset IPC socket did not become ready" >&2
        return 1
      }

      if systemctl --user is-active --quiet hyprsunset.service; then
        if [ "$(hyprctl hyprsunset temperature)" = 1500 ]; then
          systemctl --user stop hyprsunset.service
        else
          apply_night
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
  #
  # The CTM lands at scanout rather than in the composited buffer, so it is
  # invisible to wlr-screencopy: a screenshot taken during night mode still
  # shows the untransformed colours. Verify this one by eye, or by reading the
  # "Calculated the CTM to be ..." line the service logs on every profile load.
  services.hyprsunset = {
    enable = true;
    settings = {
      profile = [
        {
          time = "06:00";
          temperature = dayTemperature;
          gamma = dayGamma;
        }
        {
          time = "16:00";
          temperature = nightTemperature;
          gamma = 1.0;
        }
      ];
    };
  };

  home.packages = [
    hyprsunsetNight
    hyprsunsetWarmth
  ];
}
