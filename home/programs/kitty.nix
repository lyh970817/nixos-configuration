# Kitty Terminal Configuration
#
# Kitty exists only for the dedicated explanation Neovim window (launched as
# `kitty --detach --class explanation-nvim ... nvim <file>` by explainctl): it
# is the Kitty Graphics Protocol terminal that Snacks.image and
# render-latex.nvim draw images through. Foot remains the default terminal for
# everything else; nothing here changes Foot's role or its signal/relink
# phosphor path.
{ lib, pkgs, ... }:

let
  palettes = import ../palettes.nix;

  # The same rung-for-rung ANSI assignment as home/programs/foot.nix
  # (mkDarkTheme), translated to kitty option names, so the explanation window
  # inherits the emphasis hierarchy every TUI was tuned against. See foot.nix
  # for the per-slot rationale (Claude Code's chalk map, diff colours, the
  # bright0/236 slab split); the comments are not repeated here.
  #
  # Not portable to kitty: foot's dim0-7 (kitty renders SGR 2 by dimming the
  # base colour instead of a second table) and foot's search-box/jump-label/
  # scrollback-indicator UI colours (no kitty equivalent).
  mkTheme = p: ''
    background #${p.background}
    foreground #${p.foreground}
    selection_foreground #${p.background}
    selection_background #${p.accent}
    cursor #${p.accent}
    cursor_text_color #${p.background}
    color0 #${p.raisedBlack}
    color1 #${p.mutedText}
    color2 #${p.secondaryText}
    color3 #${p.accent}
    color4 #${p.accent}
    color5 #${p.foreground}
    color6 #${p.accent}
    color7 #${p.secondaryText}
    color8 #${p.mutedText}
    color9 #${p.secondaryText}
    color10 #${p.hot}
    color11 #${p.accent}
    color12 #${p.bright}
    color13 #${p.foreground}
    color14 #${p.foreground}
    color15 #${p.foreground}
    color236 #${p.subtleBorder}
  '';

  # Startup-time phosphor selection. Kitty cannot follow foot's SIGUSR1/SIGUSR2
  # live swap (live re-theming of running kitty windows is deliberately out of
  # scope), but a window must at least *open* in the currently selected
  # phosphor. `geninclude` runs this at every kitty startup: it reads the
  # runtime state the `phosphor` command maintains ($XDG_RUNTIME_DIR/
  # phosphor-mode), and when that is absent (fresh boot: XDG_RUNTIME_DIR is
  # tmpfs) falls back to decoding the foot.ini symlink phosphor also relinks,
  # which persists across boots. Anything unrecognised — including light mode's
  # light.ini — lands on the active profile.
  phosphorTheme = ''
    #!/bin/sh
    themes="$HOME/.config/kitty/themes"

    state="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/phosphor-mode"
    mode=""
    [ -r "$state" ] && mode="$(cat "$state")"

    if [ ! -f "$themes/$mode.conf" ]; then
      target="$(readlink "$HOME/.config/foot/foot.ini" 2>/dev/null || true)"
      case "$target" in
        */dark-swapped.ini) mode="${palettes.alternateName}" ;;
        */dark-*.ini)
          mode="''${target##*/dark-}"
          mode="''${mode%.ini}"
          ;;
        *) mode="${palettes.activeName}" ;;
      esac
    fi

    [ -f "$themes/$mode.conf" ] || mode="${palettes.activeName}"
    cat "$themes/$mode.conf"
  '';

  kittyConf = ''
    # Ported from home/programs/foot.nix (dark variant): Hack Nerd Font at
    # size 12 with 8px padding.
    font_family      Hack Nerd Font
    bold_font        Hack Nerd Font Bold
    italic_font      Hack Nerd Font Italic
    bold_italic_font Hack Nerd Font Bold Italic
    font_size 12.0
    window_padding_width 8

    # foot: [cursor] style=block, blink=yes, blink-rate=500. Kitty stops
    # blinking after 15s by default; 0 blinks indefinitely like foot.
    cursor_shape block
    cursor_blink_interval 0.5
    cursor_stop_blinking_after 0

    # foot: selection-target=clipboard — selecting copies straight to the
    # clipboard — and Shift+Insert pastes the clipboard rather than the
    # primary selection (kitty's default for it is paste_from_selection).
    # ctrl+shift+v is kitty's default clipboard paste, kept explicit to mirror
    # foot's clipboard-paste binding list.
    copy_on_select yes
    map ctrl+shift+v paste_from_clipboard
    map shift+insert paste_from_clipboard

    # The explanation window hosts nvim, which guards unsaved changes itself;
    # kitty's own "a program is running" close prompt would fire on every
    # close.
    confirm_os_window_close 0

    # The explicit terminal sequences foot's [text-bindings] preserve for
    # tmux, Codex, and Herdr, emitted byte-identically so keymaps behave the
    # same inside the explanation window.
    map ctrl+1 send_text all \x1b[49;5u
    map ctrl+shift+1 send_text all \x1b[49;6u
    map alt+shift+enter send_text all \x1b[21;2~
    map ctrl+enter send_text all \x1b[13;5u
    map shift+enter send_text all \x1b[13;2u
    map alt+enter send_text all \x1b[13;3u

    # Static fallback palette, then the startup-selected phosphor on top (a
    # later option wins in kitty.conf). If the geninclude script ever fails,
    # the window still opens on the active profile instead of kitty defaults.
    include themes/${palettes.activeName}.conf
    geninclude phosphor-theme.sh
  '';
in
{
  home.packages = [
    pkgs.kitty
    # Snacks.image support in the explanation window: ImageMagick converts
    # non-PNG images for the graphics protocol; Ghostscript rasterizes PDFs.
    # (ImageMagick is also in home/packages/desktop.nix; listed here too so
    # the explanation stack stays self-describing.)
    pkgs.imagemagick
    pkgs.ghostscript
  ];

  xdg.configFile = {
    "kitty/kitty.conf".text = kittyConf;
    "kitty/phosphor-theme.sh" = {
      text = phosphorTheme;
      executable = true;
    };
  }
  # Every phosphor profile as a kitty theme, same naming idea as foot's
  # themes/dark-<name>.ini set, so the geninclude script can resolve any
  # profile name the `phosphor` state file or foot.ini symlink carries.
  // lib.mapAttrs' (name: p: lib.nameValuePair "kitty/themes/${name}.conf" { text = mkTheme p; }) (
    palettes.profiles // palettes.previewProfiles
  );
}
