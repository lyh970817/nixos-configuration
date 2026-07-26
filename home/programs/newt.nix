# Newt (nmtui) Theme Files Configuration
# Managed by home-manager
# Original: ~/.config/newt/themes/
# Theme switching handled by darkman hooks (symlinks to current_theme)
# Consumed by shell.nix's NEWT_COLORS export via the current_theme symlink
# created by switch-dark/switch-light in desktop/theming.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Claude Code's dark-ansi theme forced several ANSI slots away from the
  # original Matrix palette in programs/alacritty.nix. Newt names colors rather
  # than addressing hex, so nmtui inherits those tweaks — and because it paints
  # its whole backdrop with ANSI black, the lifted black turns the background
  # into a dark green wash instead of the terminal's black.
  #
  # Restore the original values for the life of the process with OSC 4, then
  # reset just these slots with OSC 104 so unrelated palette state survives.
  originalSlots = {
    "0" = "#000000"; # black — nmtui backdrop; lifted to #0C3A0E so Claude Code's ANSI-black selected row stays visible
    "7" = "#4AB34D"; # white — receded to #2E9031 so Claude Code's secondary text reads as secondary
    "10" = "#2E9031"; # bright green — lifted to #7CDC7F so Claude Code's selected menu entry is distinguishable
    "12" = "#4AB34D"; # bright blue — retuned to #63C766 so Claude Code's fuzzy-match fragments read as accents
  };

  osc = lib.concatStrings (lib.mapAttrsToList (i: c: ''\033]4;${i};${c}\007'') originalSlots);
  resetOsc = lib.concatStrings (lib.mapAttrsToList (i: _: ''\033]104;${i}\007'') originalSlots);

  # Shadows the NetworkManager nmtui on PATH so both the launcher and an
  # interactive shell get the shim.
  nmtui = pkgs.writeShellScriptBin "nmtui" ''
    # The light e-ink palette was never retuned, so only shim in dark mode.
    case "$(readlink "$HOME/.config/newt/current_theme" 2>/dev/null)" in
      */dark)
        trap 'printf "${resetOsc}"' EXIT INT TERM
        printf "${osc}"
        ;;
    esac

    ${pkgs.networkmanager}/bin/nmtui "$@"
  '';
in

{
  home.packages = [ nmtui ];

  # Theme files for darkman switching
  home.file = {
    ".config/newt/themes/dark".text = ''
      root=green,black:window=green,black:border=brightgreen,black:listbox=green,black:actlistbox=black,brightgreen:sellistbox=brightgreen,black:actsellistbox=black,green:textbox=green,black:acttextbox=brightgreen,black:entry=brightgreen,black:disentry=white,black:checkbox=green,black:actcheckbox=green,black:button=black,brightgreen:actbutton=green,black:compactbutton=green,black:actcompactbutton=black,brightgreen:label=brightgreen,black:title=brightgreen,black:roottext=green,black:emptyscale=green,black:fullscale=black,brightgreen:shadow=black,black
    '';

    ".config/newt/themes/light".text = ''
      root=black,white;window=black,white;border=black,white;textbox=black,white;button=white,black;compactbutton=black,white;actbutton=white,black;checkbox=black,white;actcheckbox=white,black;entry=black,white;disentry=gray,white;label=black,white;listbox=black,white;actlistbox=white,black;sellistbox=black,gray;actsellistbox=white,black
    '';
  };
}
