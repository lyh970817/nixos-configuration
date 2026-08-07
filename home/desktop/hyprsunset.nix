{ pkgs, ... }:

let
  dayTemperature = 6500;
  dayGamma = 1.0;

  # Night mode is not a warmth filter on this machine. It is the transform that
  # turns the green phosphor console into an amber one.
  #
  # hyprsunset's CTM is strictly diagonal: each channel is scaled by
  # gamma * blackbody(T)/255, so every colour on screen gets the *same* three
  # gains. Green cannot be rotated onto amber exactly, because the two ladders
  # do not share an internal hue ramp — the red:green ratio that green needs
  # multiplying by runs from 1.8 at the dark end to 3.7 in the mid tones, and
  # one CTM can only supply a single value. These numbers are the least bad
  # compromise, found by sweeping temperature and gamma against the CIELAB
  # distance from each transformed green rung to its amber counterpart:
  # mean dE 13.9, and dE 9.9 on the foreground rung, which is the one actually
  # read. See home/palettes.nix for the two ladders being matched.
  #
  # Keep this a multiple of 100. matrixForKelvin does `temp /= 100` on an
  # integer, so the temperature is quantised to hundreds: 1100 and 1199 produce
  # exactly the same matrix, and 1080 would silently behave as 1000.
  #
  # 1100 K is below the 1900 K point where hyprsunset's blue term reaches zero,
  # so the result carries no blue at all. Amber's small blue component is lost
  # and the transformed palette is a purer orange than the amber profile is.
  # That is a consequence of the fit rather than an oversight: any temperature
  # warm enough to make red dominate green has already clamped blue to zero.
  nightTemperature = 1100;

  # 280%. Green's red channel is far weaker than amber's, so the transform has
  # to amplify, not merely attenuate. hyprsunset's --gamma help text claims a
  # 200% ceiling but nothing enforces it; the real limit is the max-gamma
  # config value below. Gains above 1.0 clip, so the top two rungs saturate
  # their red channel and the brightest end of the ladder compresses slightly.
  # It also amplifies red across every other surface, so photos and video look
  # heavily blown out while night mode is on.
  nightGamma = 2.80;

  # Ceiling for the gamma above; hyprsunset refuses the profile outright if
  # gamma exceeds it. Expressed in percent, unlike the per-profile gamma.
  maxGammaPercent = 300;

  nightGammaPercent = toString (builtins.floor (nightGamma * 100.0));

  hyprsunsetToggle = pkgs.writeShellApplication {
    name = "hyprsunset-toggle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
      pkgs.systemd
    ];
    text = ''
      # Both halves of the transform have to be sent. Temperature alone would
      # leave gamma at whatever the time-of-day profile loaded, and at gamma
      # 100% an 1100 K CTM is a very dark red wash rather than amber.
      apply_night() {
        hyprctl hyprsunset temperature ${toString nightTemperature} >/dev/null 2>&1 || return 1
        hyprctl hyprsunset gamma ${nightGammaPercent} >/dev/null 2>&1 || return 1
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
        current_temperature=$(hyprctl hyprsunset temperature)
        if [ "$current_temperature" = "${toString nightTemperature}" ]; then
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
  # shows untransformed green. Verify this one by eye, or by reading the
  # "Calculated the CTM to be ..." line the service logs on every profile load.
  services.hyprsunset = {
    enable = true;
    settings = {
      max-gamma = maxGammaPercent;
      profile = [
        {
          time = "06:00";
          temperature = dayTemperature;
          gamma = dayGamma;
        }
        {
          time = "16:00";
          temperature = nightTemperature;
          gamma = nightGamma;
        }
      ];
    };
  };

  home.packages = [ hyprsunsetToggle ];
}
