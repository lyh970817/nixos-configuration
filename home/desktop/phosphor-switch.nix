# Instant switch between the two real phosphor palettes.
#
# This is a genuine palette swap, not the night-mode CTM: both sides are the
# actual profiles from ../palettes.nix, unfiltered. Foot keeps two complete
# colour themes in one config and switches on SIGUSR1/SIGUSR2, so every open
# window repaints at once with no reload, no relaunch, and no rebuild.
#
# What it cannot reach: anything that hardcodes hex instead of naming an ANSI
# slot. fzf, btop, the Yazi flavor, mako, rofi, Hyprland's borders and the GTK
# theme were all built from whichever profile was active, and only a rebuild
# moves them. Everything that reaches colour through an ANSI slot — the shell,
# Starship, Claude Code, nvim, tmux content, man pages — follows instantly.
{ pkgs, ... }:

let
  palettes = import ../palettes.nix;
  activeName = palettes.activeName;
  alternateName = palettes.alternateName;
in
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "phosphor";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.procps
      ];
      text = ''
        state="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/phosphor-mode"
        themes="$HOME/.config/foot/themes"

        current() {
          if [ -r "$state" ]; then cat "$state"; else printf '%s' "${activeName}"; fi
        }

        usage() {
          cat <<EOF
        usage: phosphor [${activeName}|${alternateName}|toggle|status]

          ${activeName}   the built-in profile   (foot theme slot 1)
          ${alternateName}   the alternate profile  (foot theme slot 2)
          toggle  flip between them
          status  print the current selection

        Repaints every running foot window instantly. Programs that hardcode
        hex (fzf, btop, yazi, mako, rofi, Hyprland borders, GTK) keep the
        profile they were built with until a rebuild.
        EOF
        }

        target="''${1:-toggle}"
        [ "$target" = "toggle" ] && {
          if [ "$(current)" = "${activeName}" ]; then target="${alternateName}"; else target="${activeName}"; fi
        }

        case "$target" in
          status) current; echo; exit 0 ;;
          -h | --help | help) usage; exit 0 ;;
          ${activeName}) signal=USR1; link="$themes/dark.ini" ;;
          ${alternateName}) signal=USR2; link="$themes/dark-swapped.ini" ;;
          *) usage >&2; exit 1 ;;
        esac

        # Relink first so any window opened from here on starts on the chosen
        # palette, then signal the ones already running. Without the relink the
        # two would disagree the moment a new terminal opens.
        ln -sfn "$link" "$HOME/.config/foot/foot.ini"

        # -x so this never matches footclient or an unrelated command line.
        pkill -"$signal" -x foot 2>/dev/null || true

        printf '%s' "$target" > "$state"
        printf 'phosphor: %s\n' "$target"
      '';
    })
  ];
}
