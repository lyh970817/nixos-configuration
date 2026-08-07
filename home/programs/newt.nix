# Newt (nmtui) Theme Files Configuration
# Managed by home-manager
# Original: ~/.config/newt/themes/
# Both dark and light variants are written unconditionally by this file;
# shell.nix selects which one to use per-session based on THEME_MODE and
# exports it as NEWT_COLORS.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Claude Code's dark-ansi theme forced several ANSI slots away from the
  # original dark palette in programs/alacritty.nix. Newt names colors rather
  # than addressing hex, so nmtui inherits those tweaks — and because it paints
  # its whole backdrop with ANSI black, the lifted black turns the background
  # into a dark amber wash instead of the terminal's black.
  #
  # Restore the original values for the life of the process with OSC 4, then
  # reset just these slots with OSC 104 so unrelated palette state survives.
  originalSlots = {
    "0" = "#080705"; # black — nmtui backdrop; lifted to #110E08 so Claude Code's ANSI-black selected row stays visible
    "7" = "#D99B32"; # white — receded to #9B6D24 so Claude Code's secondary text reads as secondary
    "10" = "#9B6D24"; # bright amber — lifted to #FFD064 so Claude Code's selected menu entry is distinguishable
    "12" = "#D99B32"; # bright blue — retuned to #EDB144 so Claude Code's fuzzy-match fragments read as accents
  };

  osc = lib.concatStrings (lib.mapAttrsToList (i: c: ''\033]4;${i};${c}\007'') originalSlots);
  resetOsc = lib.concatStrings (lib.mapAttrsToList (i: _: ''\033]104;${i}\007'') originalSlots);

  # Shadows the NetworkManager nmtui on PATH so both the launcher and an
  # interactive shell get the shim.
  nmtui = pkgs.writeShellScriptBin "nmtui" ''
    # The light e-ink palette was never retuned, so only shim in dark mode.
    # THEME_MODE is the per-session mode: set by theme-hold for ssh/mosh
    # sessions, otherwise defaulted from this machine's own monitor by
    # shell.nix. The desktop launcher runs `zsh -i -c nmtui`, so it picks up
    # that same default. (This replaced the old newt/current_theme symlink,
    # which no longer exists.)
    case "''${THEME_MODE:-}" in
      dark)
        trap 'printf "${resetOsc}"' EXIT INT TERM
        printf "${osc}"
        ;;
    esac

    ${pkgs.networkmanager}/bin/nmtui "$@"
  '';
in

{
  home.packages = [ nmtui ];

  # Per-mode (dark/light) theme variant files, selected at shell startup by
  # THEME_MODE (set by theme-hold for ssh/mosh sessions, otherwise defaulted
  # from the local monitor)
  home.file = {
    ".config/newt/themes/dark".text = ''
      root=amber,black:window=amber,black:border=brightamber,black:listbox=amber,black:actlistbox=black,brightamber:sellistbox=brightamber,black:actsellistbox=black,amber:textbox=amber,black:acttextbox=brightamber,black:entry=brightamber,black:disentry=white,black:checkbox=amber,black:actcheckbox=amber,black:button=black,brightamber:actbutton=amber,black:compactbutton=amber,black:actcompactbutton=black,brightamber:label=brightamber,black:title=brightamber,black:roottext=amber,black:emptyscale=amber,black:fullscale=black,brightamber:shadow=black,black
    '';

    ".config/newt/themes/light".text = ''
      root=black,white;window=black,white;border=black,white;textbox=black,white;button=white,black;compactbutton=black,white;actbutton=white,black;checkbox=black,white;actcheckbox=white,black;entry=black,white;disentry=gray,white;label=black,white;listbox=black,white;actlistbox=white,black;sellistbox=black,gray;actsellistbox=white,black
    '';
  };
}
