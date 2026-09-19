# lsd as ls, themed through ANSI slots only, so it follows the phosphor
# profile (../palettes.nix) and never names a hex.
#
# Both modes are written out unconditionally under ~/.config/lsd-themes and
# the `lsd` wrapper below picks one per process from THEME_MODE, as newt.nix
# does for nmtui. lsd 1.2.0 can only load a custom theme from
# <config dir>/lsd/colors.yaml and checks ~/.config/lsd before
# XDG_CONFIG_HOME, so the wrapper points XDG_CONFIG_HOME at the mode's tree
# and nothing may ever be installed under ~/.config/lsd.
#
# Dark slots, for the rung each carries in programs/foot.nix:
#
#   8   mutedText      dashes, tree edges, empty sizes
#   2   secondaryText  group, old dates, small sizes
#   4   accent         write bit, day-old dates, medium sizes
#   5   foreground     user, read bit
#   12  bright         exec bit, fresh dates, large sizes
#   10  hot            conflicts only
#
# Light has two tones: 0 (black) carries, 8 (grey) recedes, and emphasis is
# bold or underline, the vocabulary shell.nix's light syntax highlighting
# already uses.
#
# File-type colours (directories, links, executables) are not settable in
# the theme file -- the field is skipped and an entry for it voids the whole
# file -- and come from LS_COLORS, exported per mode below and shared with
# GNU ls, fd, tree and fzf. It replaces oh-my-zsh's dircolors default, whose
# per-extension entries reach outside the ladder.
{
  lib,
  pkgs,
  ...
}:

let
  yaml = pkgs.formats.yaml { };

  darkTheme = {
    user = 5;
    group = 2;
    permission = {
      read = 5;
      write = 4;
      exec = 12;
      exec-sticky = 12;
      no-access = 8;
      octal = 5;
      acl = 2;
      context = 2;
    };
    date = {
      hour-old = 12;
      day-old = 4;
      older = 2;
    };
    size = {
      none = 8;
      small = 2;
      medium = 4;
      large = 12;
    };
    inode = {
      valid = 2;
      invalid = 8;
    };
    links = {
      valid = 2;
      invalid = 8;
    };
    tree-edge = 8;
    git-status = {
      default = 8;
      unmodified = 8;
      ignored = 8;
      new-in-index = 12;
      new-in-workdir = 12;
      typechange = 4;
      deleted = 1;
      renamed = 4;
      modified = 4;
      conflicted = 10;
    };
  };

  lightTheme = {
    user = 0;
    group = 8;
    permission = {
      read = 0;
      write = 0;
      exec = 0;
      exec-sticky = 0;
      no-access = 8;
      octal = 0;
      acl = 8;
      context = 8;
    };
    date = {
      hour-old = 0;
      day-old = 0;
      older = 8;
    };
    size = {
      none = 8;
      small = 8;
      medium = 0;
      large = 0;
    };
    inode = {
      valid = 0;
      invalid = 8;
    };
    links = {
      valid = 8;
      invalid = 8;
    };
    tree-edge = 8;
    git-status = {
      default = 8;
      unmodified = 8;
      ignored = 8;
      new-in-index = 0;
      new-in-workdir = 0;
      typechange = 0;
      deleted = 0;
      renamed = 0;
      modified = 0;
      conflicted = 0;
    };
  };

  lsColors = {
    dark = builtins.concatStringsSep ":" [
      "rs=0"
      "di=01;94" # bright: directories are the landmarks
      "tw=01;94"
      "ow=01;94"
      "st=01;94"
      "ex=01;35" # foreground, bold
      "su=01;35"
      "sg=01;35"
      "ln=36" # accent
      "pi=33"
      "so=33"
      "do=33"
      "bd=33"
      "cd=33"
      "or=01;31" # mutedText: broken links fade
      "mi=31"
      "mh=00"
      "ca=00"
    ];
    light = builtins.concatStringsSep ":" [
      "rs=0"
      "di=01;30" # bold black
      "tw=01;30"
      "ow=01;30"
      "st=01;30"
      "ex=04;30" # underlined black
      "su=04;30"
      "sg=04;30"
      "ln=30"
      "pi=30"
      "so=30"
      "do=30"
      "bd=30"
      "cd=30"
      "or=01;90" # grey: broken links fade
      "mi=90"
      "mh=00"
      "ca=00"
    ];
  };

  themeTree = name: theme: {
    ".config/lsd-themes/${name}/lsd/config.yaml".source = yaml.generate "lsd-config-${name}" {
      color.theme = "custom";
    };
    ".config/lsd-themes/${name}/lsd/colors.yaml".source = yaml.generate "lsd-colors-${name}" theme;
  };

  # THEME_MODE is the per-session mode; when it is unset (a launcher, a
  # script run outside a shell) fall back to this machine's own monitor, the
  # same way the nmtui and btop wrappers do.
  lsd = pkgs.writeShellScriptBin "lsd" ''
    mode="''${THEME_MODE:-}"
    if [ -z "$mode" ]; then
      case "$(readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
        *dark.lua) mode=dark ;;
        *) mode=light ;;
      esac
    fi
    export XDG_CONFIG_HOME="$HOME/.config/lsd-themes/$mode"
    exec ${pkgs.lsd}/bin/lsd "$@"
  '';
in

{
  # The wrapper shadows the real binary on PATH; the package stays for its
  # shell completions.
  home.packages = [
    (lib.hiPrio lsd)
    pkgs.lsd
  ];

  home.file = themeTree "dark" darkTheme // themeTree "light" lightTheme;

  programs.zsh = {
    shellAliases = {
      ls = "lsd";
      ll = "lsd -l";
      la = "lsd -A";
      lt = "lsd --tree";
      lla = "lsd -lA";
      llt = "lsd -l --tree";
    };

    # After shell.nix has established THEME_MODE and oh-my-zsh has exported
    # its dircolors default.
    initContent = lib.mkAfter ''
      case "$THEME_MODE" in
      dark) export LS_COLORS='${lsColors.dark}' ;;
      light) export LS_COLORS='${lsColors.light}' ;;
      esac
    '';
  };
}
