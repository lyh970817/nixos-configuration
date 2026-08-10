# Newt (nmtui) Theme Files Configuration
# Managed by home-manager
# Original: ~/.config/newt/themes/
# Both dark and light variants are written unconditionally by this file;
# shell.nix selects which one to use per-session based on THEME_MODE and
# exports it as NEWT_COLORS (which whiptail and any other newt program also
# read). The nmtui wrapper below sets the same variable itself rather than
# trusting the environment — see there for why.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;

  # newt resolves colours by NAME against a fixed list -- black, red, green,
  # brown, blue, magenta, cyan, lightgray, gray, brightred, brightgreen,
  # yellow, brightblue, brightmagenta, brightcyan, white -- which is just
  # ANSI 0-15 under other names. "amber" and "brightamber" are not on it, so
  # the rename in 6239b4f1 silently voided every rule that used them and
  # dropped nmtui to newt's built-in blue defaults.
  #
  # So the names below are chosen for the *index* they resolve to, not for the
  # hue they read as: the terminal theme in programs/foot.nix lays the
  # phosphor ladder over ANSI 0-15, and these pick the slots holding the
  # rungs each role needs.
  #
  #   black       0   raisedBlack     the backdrop, and the text on reversed rows
  #   brown       3   secondaryText   receded, for disabled entries
  #   blue        4   accent          reversed fills (see the clamp below)
  #   magenta     5   foreground      body text
  #   brightblue 12   bright          borders, titles, labels, entries
  #
  # Backgrounds are restricted to 0-7: slang emits reversed fills as SGR 40-47
  # and clamps a bright name down to its regular counterpart, so a fill can
  # never reach `bright` or `hot`. `blue` (accent) is the brightest rung a fill
  # can actually land on, which is also what the rofi, foot and btop
  # selections use.
  #
  # An earlier revision instead named green/brightgreen and corrected the slots
  # at runtime with an OSC 4 shim. That was removed: OSC 4 only survives when
  # the escape reaches the terminal, so it silently did nothing under a tmux
  # popup or a nested multiplexer, and it mutated the terminal's palette for
  # the life of the process. Naming the right slot needs no escape at all.
  darkTheme = builtins.concatStringsSep ":" [
    "root=magenta,black"
    "window=magenta,black"
    "border=brightblue,black"
    "listbox=magenta,black"
    "actlistbox=black,magenta"
    "sellistbox=brightblue,black"
    "actsellistbox=black,blue"
    "textbox=magenta,black"
    "acttextbox=brightblue,black"
    "entry=brightblue,black"
    "disentry=brown,black"
    "checkbox=magenta,black"
    "actcheckbox=magenta,black"
    "button=black,magenta"
    "actbutton=magenta,black"
    "compactbutton=magenta,black"
    "actcompactbutton=black,magenta"
    "label=brightblue,black"
    "title=brightblue,black"
    "roottext=magenta,black"
    "emptyscale=magenta,black"
    "fullscale=black,magenta"
    "shadow=black,black"
  ];

  # Unlike the shared newt theme above, nmtui should paint its unselected
  # surfaces with the terminal's true background. Slang accepts `default` as a
  # special colour and emits the terminal default instead of ANSI 0, whose
  # deliberately raised palette rung otherwise makes nmtui look grey.
  nmtuiDarkTheme = builtins.replaceStrings [ ",black" ] [ ",default" ] darkTheme;

  lightTheme = builtins.concatStringsSep ";" [
    "root=black,white"
    "window=black,white"
    "border=black,white"
    "textbox=black,white"
    "button=white,black"
    "compactbutton=black,white"
    "actbutton=white,black"
    "checkbox=black,white"
    "actcheckbox=white,black"
    "entry=black,white"
    "disentry=gray,white"
    "label=black,white"
    "listbox=black,white"
    "actlistbox=white,black"
    "sellistbox=black,gray"
    "actsellistbox=white,black"
  ];

  # Shadows the NetworkManager nmtui on PATH so both the launcher and an
  # interactive shell get the theme.
  nmtui = pkgs.writeShellScriptBin "nmtui" ''
    # NEWT_COLORS is normally exported by shell.nix, but the environment is not
    # a channel this can rely on. A tmux server freezes the environment it was
    # started with and hands that to every process it spawns, so a pane can
    # still be serving a NEWT_COLORS from before the last rebuild long after
    # the theme files on disk were corrected -- and because an unrecognised
    # colour name voids the whole rule it appears in, a stale one does not
    # degrade gracefully, it drops nmtui to newt's built-in defaults. Only an
    # interactive zsh re-reads the file; anything launched any other way (a
    # bare `nmtui` under a stale server, a desktop entry, a keybinding) keeps
    # the frozen value. Setting it here makes the theme this build generated
    # the one that is used, whatever the caller's environment says.
    #
    # THEME_MODE is the per-session mode: set by theme-hold for ssh/mosh
    # sessions, otherwise defaulted from this machine's own monitor by
    # shell.nix. When it is unset (a desktop entry, a systemd unit) fall back
    # to this machine's own monitor by reading the hypr current-theme symlink
    # directly, the same way the btop wrapper does.
    mode="''${THEME_MODE:-}"
    if [ -z "$mode" ]; then
      case "$(readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
        *dark.lua) mode=dark ;;
        *) mode=light ;;
      esac
    fi

    case "$mode" in
      light) export NEWT_COLORS='${lightTheme}' ;;
      *) export NEWT_COLORS='${nmtuiDarkTheme}' ;;
    esac

    exec ${pkgs.networkmanager}/bin/nmtui "$@"
  '';
in

{
  home.packages = [ nmtui ];

  # Per-mode (dark/light) theme variant files, selected at shell startup by
  # THEME_MODE (set by theme-hold for ssh/mosh sessions, otherwise defaulted
  # from the local monitor). These are what whiptail and any other newt
  # program pick up; nmtui itself does not depend on them.
  home.file = {
    ".config/newt/themes/dark".text = darkTheme + "\n";
    ".config/newt/themes/light".text = lightTheme + "\n";
  };
}
