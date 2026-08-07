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
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;

  # Claude Code's dark-ansi theme forced several ANSI slots away from the
  # original dark palette in programs/alacritty.nix. Newt names colors rather
  # than addressing hex, so nmtui inherits those tweaks — and because it paints
  # its whole backdrop with ANSI black, the lifted black turns the background
  # into a dark amber wash instead of the terminal's black.
  #
  # Restore the original values for the life of the process with OSC 4, then
  # reset just these slots with OSC 104 so unrelated palette state survives.
  # Slots are chosen for the roles the theme string below actually names, and
  # every one of those must stay legible: newt has no notion of a "dim" colour,
  # so a rung that is merely decorative elsewhere becomes body text here.
  originalSlots = {
    "0" = "#${p.background}"; # black — the backdrop, and the text colour on every reversed element
    "2" = "#${p.foreground}"; # green — body text; the terminals map this rung to mutedText, which is far too dim to read a form in
    "7" = "#${p.foreground}"; # white — disabled entries
    "10" = "#${p.bright}"; # brightgreen — borders, titles, labels, and the fill behind reversed rows, so it must outrank green
    "12" = "#${p.foreground}"; # bright blue — retuned by Claude Code's theme so its fuzzy-match fragments read as accents
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
    # newt resolves colours by NAME against a fixed list: black, red, green,
    # brown, blue, magenta, cyan, lightgray, gray, brightred, brightgreen,
    # yellow, brightblue, brightmagenta, brightcyan, white. "amber" and
    # "brightamber" are not on it, so the rename in 6239b4f1 silently voided
    # every rule that used them. Only these names are safe, and the hue comes
    # from the OSC 4 slots above rather than from the name -- "green" here is
    # whatever slot 2 has been set to.
    ".config/newt/themes/dark".text = ''
      root=green,black:window=green,black:border=brightgreen,black:listbox=green,black:actlistbox=black,brightgreen:sellistbox=brightgreen,black:actsellistbox=black,green:textbox=green,black:acttextbox=brightgreen,black:entry=brightgreen,black:disentry=white,black:checkbox=green,black:actcheckbox=green,black:button=black,brightgreen:actbutton=green,black:compactbutton=green,black:actcompactbutton=black,brightgreen:label=brightgreen,black:title=brightgreen,black:roottext=green,black:emptyscale=green,black:fullscale=black,brightgreen:shadow=black,black
    '';

    ".config/newt/themes/light".text = ''
      root=black,white;window=black,white;border=black,white;textbox=black,white;button=white,black;compactbutton=black,white;actbutton=white,black;checkbox=black,white;actcheckbox=white,black;entry=black,white;disentry=gray,white;label=black,white;listbox=black,white;actlistbox=white,black;sellistbox=black,gray;actsellistbox=white,black
    '';
  };
}
