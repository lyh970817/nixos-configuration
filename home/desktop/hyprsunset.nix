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
  # multiplying by runs from 1.68 at the dark end to 2.82 in the mid tones, and
  # one CTM can only supply a single value. These numbers are the least bad
  # compromise, found by sweeping temperature and gamma against the CIELAB
  # distance from each transformed green rung to its amber counterpart:
  # mean dE 13.2, and dE 13.0 on the foreground rung. See home/palettes.nix for
  # the two ladders being matched.
  #
  # Keep this a multiple of 100. matrixForKelvin does `temp /= 100` on an
  # integer, so the temperature is quantised to hundreds: 1400 and 1499 produce
  # exactly the same matrix, and 1080 would silently behave as 1000.
  #
  # 1400 K is below the 1900 K point where hyprsunset's blue term reaches zero,
  # so the result carries no blue at all. Amber's small blue component is lost
  # and the transformed palette is a purer orange than the amber profile is.
  # That is a consequence of the fit rather than an oversight: any temperature
  # warm enough to make red dominate green has already clamped blue to zero.
  # Zeroing blue is also the single biggest circadian win available here —
  # a conventional 2700 K filter still passes some.
  nightTemperature = 1400;

  # 200%. Amplification is unavoidable, not a preference: at gamma 100% a CTM
  # can only attenuate, so red can never exceed green and the "amber" comes out
  # olive (the foreground would land on #585700, R=88 G=87). Reaching amber at
  # all requires a red gain above 1.
  #
  # 200% is hyprsunset's documented maximum, so this no longer runs past a
  # stated limit the way the previous 280% did. Gains above 1.0 still clip, so
  # the top of the ladder compresses slightly, and red is amplified across every
  # other surface too — photos and video look blown out while night mode is on.
  #
  # This is also the circadian lever. Melanopic exposure for a typical terminal
  # screen, relative to daytime: 0.40x here, against 0.50x at the old 280%, and
  # 0.32x for a typical 2700 K filter. Dropping to 1600 K / 160% would reach
  # that 0.32x at the cost of a visibly looser amber (mean dE 17.4).
  nightGamma = 2.00;

  # Ceiling for the gamma above; hyprsunset refuses the profile outright if
  # gamma exceeds it, and its own default is 100. Expressed in percent, unlike
  # the per-profile gamma.
  maxGammaPercent = 200;

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
      # 100% a 1400 K CTM is a dim olive wash rather than amber.
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
