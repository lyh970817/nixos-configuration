# Kitty Terminal Configuration
#
# Kitty is the default terminal (keybinds, scratchpads, the btop dashboard —
# see dotfiles/hypr/hyprland.lua and home/programs/dotfiles.nix) and also
# hosts the dedicated explanation Neovim window (launched as
# `kitty --detach --class explanation-nvim ... nvim <file>` by explainctl),
# drawing images through the Kitty Graphics Protocol for Snacks.image and
# render-latex.nvim. Foot stays installed until the migration settles; its
# signal/relink phosphor path (home/desktop/phosphor-switch.nix,
# home/desktop/theming.nix) remains the theme state kitty reads at startup.
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

  # E-ink palette, matching foot's light theme slot for slot. Keeping every
  # ANSI entry monochrome is what lets palette-relative TUIs share one light
  # vocabulary instead of reintroducing coloured syntax on the Paperlike.
  lightTheme = ''
    background #FFFFFF
    foreground #000000
    selection_foreground #FFFFFF
    selection_background #000000
    cursor #000000
    cursor_text_color #FFFFFF
    color0 #000000
    color1 #000000
    color2 #000000
    color3 #000000
    color4 #000000
    color5 #000000
    color6 #000000
    color7 #FFFFFF
    color8 #808080
    color9 #808080
    color10 #808080
    color11 #808080
    color12 #808080
    color13 #808080
    color14 #808080
    color15 #FFFFFF
    color236 #E8E8E8
  '';

  # Startup-time phosphor selection. Kitty cannot follow foot's SIGUSR1/SIGUSR2
  # live swap (live re-theming of running kitty windows is deliberately out of
  # scope), but a window must at least *open* in the currently selected
  # phosphor. `geninclude` runs this at every kitty startup: it reads the
  # runtime state the `phosphor` command maintains ($XDG_RUNTIME_DIR/
  # phosphor-mode), and when that is absent (fresh boot: XDG_RUNTIME_DIR is
  # tmpfs) falls back to decoding the foot.ini symlink phosphor also relinks.
  # THEME_MODE is authoritative when a terminal belongs to a viewer session;
  # otherwise the machine's applied monitor theme is resolved at startup.
  phosphorTheme = ''
    #!/bin/sh
    themes="$HOME/.config/kitty/themes"

    session_mode="''${THEME_MODE:-}"
    if [ -z "$session_mode" ]; then
      target="$(readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null || true)"
      case "$target" in
        *light.lua) session_mode=light ;;
        *dark.lua) session_mode=dark ;;
        *)
          echo "kitty: cannot determine the viewer theme" >&2
          exit 1
          ;;
      esac
    fi

    case "$session_mode" in
      light)
        mode=light
        ;;
      dark)
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
        ;;
      *)
        echo "kitty: invalid THEME_MODE: $session_mode" >&2
        exit 1
        ;;
    esac

    cat "$themes/$mode.conf"
  '';

  # Resolve the local viewer mode before Kitty itself starts. The environment
  # then reaches both Kitty's geninclude and the terminal's complete child
  # process tree, so terminal colours and TUI colours share one snapshot.
  kittyWrapped = pkgs.symlinkJoin {
    name = "kitty-themed";
    paths = [ pkgs.kitty ];
    postBuild = ''
      rm "$out/bin/kitty"
      cat > "$out/bin/kitty" <<'WRAPPER'
      #!${pkgs.runtimeShell}
      mode="''${THEME_MODE:-}"
      if [ -z "$mode" ]; then
        target="$(${pkgs.coreutils}/bin/readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null || true)"
        case "$target" in
          *light.lua) mode=light ;;
          *dark.lua) mode=dark ;;
          *)
            echo "kitty: cannot determine the applied monitor theme" >&2
            exit 1
            ;;
        esac
      fi

      case "$mode" in
        dark | light) ;;
        *)
          echo "kitty: invalid THEME_MODE: $mode" >&2
          exit 1
          ;;
      esac

      export THEME_MODE="$mode"
      exec ${pkgs.kitty}/bin/kitty "$@"
      WRAPPER
      chmod +x "$out/bin/kitty"
    '';
  };

  kittyConf = ''
    # Ported from home/programs/foot.nix (dark variant): Hack Nerd Font at
    # size 12 with 8px padding.
    font_family      Hack Nerd Font
    bold_font        Hack Nerd Font Bold
    italic_font      Hack Nerd Font Italic
    bold_italic_font Hack Nerd Font Bold Italic
    font_size 12.0
    window_padding_width 8

    # Match foot's fontconfig CJK fallback (fc-match :lang=zh-cn → WenQuanYi
    # Zen Hei, from home/packages/fonts.nix). Kitty's own fallback picks Noto
    # Sans Mono CJK KR instead, so Chinese text rendered differently than in
    # foot. Ranges: CJK punctuation, ext A, Han, compat ideographs, fullwidth.
    symbol_map U+3000-U+303F,U+3400-U+4DBF,U+4E00-U+9FFF,U+F900-U+FAFF,U+FF00-U+FFEF WenQuanYi Zen Hei

    # Kitty's rasterizer effectively ignores fontconfig hinting (an A/B of
    # hintfull vs forced hintnone changed ~126 of 50k pixels), so the crispness
    # lever is this compositing knob, not fontconfig. "legacy" composites
    # glyphs thinner than the default "platform" gamma and measured closest to
    # foot's rendering of the same phosphor text (RMSE 0.109 vs 0.113;
    # custom "<gamma> <contrast>" values all landed further away). Kitty still
    # draws Hack a touch wider than foot — that residue is cell-metric
    # rounding, which no composition value changes.
    text_composition_strategy legacy

    # Box-drawing weight parity with foot. Kitty sizes its self-rendered box
    # glyphs in pts scaled by monitor DPI (thin/normal/thick/very-thick;
    # default 0.001, 1, 1.5, 2): at this monitor's 1.67 scale the default 1pt
    # "normal" made herdr's light pane borders (│ ─) ~3px against foot's 1px
    # hairline. 0.4pt measured exactly 1px full-intensity here and floors to
    # kitty's 1px minimum on lower-DPI outputs. Heavy lines (┃ ━) already
    # measured 5px in both terminals, so the thick weights stay default.
    box_drawing_scale 0.001, 0.4, 1.5, 2

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

    # Kitty's defaults bind these to its own next_tab/previous_tab, swallowing
    # the combos before the child sees them; no_op frees them so herdr's
    # kitty-protocol push receives CSI 9;5u/9;6u natively (as in foot).
    map ctrl+tab no_op
    map ctrl+shift+tab no_op

    # Static fallback palette, then the startup-selected phosphor on top (a
    # later option wins in kitty.conf). If the geninclude script ever fails,
    # the window still opens on the active profile instead of kitty defaults.
    include themes/${palettes.activeName}.conf
    geninclude phosphor-theme.sh
  '';
in
{
  home.packages = [
    kittyWrapped
    # Snacks.image support in the explanation window: ImageMagick converts
    # non-PNG images for the graphics protocol; Ghostscript rasterizes PDFs.
    # (ImageMagick is also in home/packages/desktop.nix; listed here too so
    # the explanation stack stays self-describing.)
    pkgs.imagemagick
    pkgs.ghostscript
    # Snacks.image math: compiles the `$...$` inline-math snippets to PDF
    # (small self-contained engine; fetches TeX assets into ~/.cache/Tectonic
    # on first use). Display math stays with render-latex.nvim's own worker.
    pkgs.tectonic
  ];

  xdg.configFile = {
    "kitty/kitty.conf".text = kittyConf;
    "kitty/phosphor-theme.sh" = {
      text = phosphorTheme;
      executable = true;
    };
    "kitty/themes/light.conf".text = lightTheme;
  }
  # Every phosphor profile as a kitty theme, same naming idea as foot's
  # themes/dark-<name>.ini set, so the geninclude script can resolve any
  # profile name the `phosphor` state file or foot.ini symlink carries.
  // lib.mapAttrs' (name: p: lib.nameValuePair "kitty/themes/${name}.conf" { text = mkTheme p; }) (
    palettes.profiles // palettes.previewProfiles
  );
}
