# Side-by-side viewer for judging the night-mode green -> amber fit.
#
# A colour transform on this machine is a CTM, and hyprland-ctm-control-v1 sets
# a CTM per *output*. There is no per-window or per-workspace scope, so two
# windows can never sit under different transforms at the same time. The way
# round it is to pre-distort one of them: `amberViaNight` in ../palettes.nix is
# amber divided by the night gains, so under night mode it renders as amber
# while an ordinary green window renders as whatever the transform makes of it.
# Both windows are then under the identical CTM and directly comparable.
{ pkgs, ... }:

let
  # Same content in both windows, so the only difference is the palette.
  demo = pkgs.writeShellScript "palette-compare-demo" ''
    printf '\n  %s\n\n' "$1"
    printf '  regular  '; for i in 0 1 2 3 4 5 6 7; do printf '\033[3%dm██████\033[0m' $i; done; printf '\n'
    printf '  bright   '; for i in 0 1 2 3 4 5 6 7; do printf '\033[9%dm██████\033[0m' $i; done; printf '\n\n'
    printf '  \033[97mforeground / normal body text\033[0m\n'
    printf '  \033[37msecondary text (SGR 37)\033[0m\n'
    printf '  \033[90mdim border text (SGR 90)\033[0m\n'
    printf '  \033[93maccent emphasis (SGR 93)\033[0m\n'
    printf '  \033[92mbright emphasis (SGR 92)\033[0m\n'
    printf '  \033[7m reverse video / critical \033[0m\n\n'
    printf '  usage ramp  '
    printf '\033[91m███░░░░░░░\033[0m 12%%  '
    printf '\033[93m███████░░░\033[0m 75%%  '
    printf '\033[92m█████████░\033[0m \033[7m !94%% \033[0m\n\n'
    read -r -n 1 -s -p "  press any key to close"
  '';
in
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "palette-compare";
      runtimeInputs = [
        pkgs.foot
        pkgs.systemd
      ];
      text = ''
        themes="$HOME/.config/foot/themes"

        # The reference window only reads as amber while the CTM is applied, so
        # refuse to mislead when night mode is off.
        if ! systemctl --user is-active --quiet hyprsunset.service; then
          cat >&2 <<'EOF'
        Night mode is off, so nothing is transformed and the reference window
        will look yellow-green rather than amber. Start it first:

            systemctl --user start hyprsunset.service     # or: hyprsunset-toggle

        Comparing with night mode off is still meaningful, but use the static
        prediction instead of the pre-compensated reference:

            palette-compare --off
        EOF
          [ "''${1:-}" = "--off" ] || exit 1
        fi

        if [ "''${1:-}" = "--off" ]; then
          left="$themes/dark-greenAsNight.ini"; left_label="PREDICTED (green x night CTM, computed)"
        else
          left="$themes/dark-amberViaNight.ini"; left_label="TARGET (real amber under night mode)"
        fi

        foot --config="$left" --title=palette-compare-left \
          -e ${demo} "$left_label" &
        foot --config="$themes/dark-green.ini" --title=palette-compare-right \
          -e ${demo} "ACTUAL (green under night mode)" &
        wait
      '';
    })
  ];
}
