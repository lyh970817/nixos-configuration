# Alacritty Terminal Configuration
# Managed by home-manager
# Original: ~/.config/alacritty/
# Theme switching handled by darkman hooks (symlinks to current.toml)
{
  config,
  lib,
  pkgs,
  ...
}:

let
  palettes = import ../palettes.nix;

  # Dark palette, addressed by ladder rung rather than by hex so any phosphor
  # profile in ../palettes.nix produces the same emphasis hierarchy. See that
  # file for why normal.black, normal.white, bright.green, and bright.blue sit
  # where they do.
  mkDarkTheme = p: ''
    # CRT console theme for Alacritty: near-black glass with a single-phosphor
    # intensity ladder standing in for the usual eight hues.

    [colors]
    # Default colors
    [colors.primary]
    background = '#${p.background}'
    foreground = '#${p.foreground}'

    # Cursor colors
    [colors.cursor]
    text = '#${p.background}'
    cursor = '#${p.accent}'

    # Selection colors. accent rather than secondaryText, because the selection
    # carries background-coloured text and the green ladder's secondaryText rung
    # is only 0.58x the luminance of amber's, taking that pairing to 2.9:1.
    # See rofi.nix.
    [colors.selection]
    text = '#${p.background}'
    background = '#${p.accent}'

    # Normal colors - the intensity ladder standing in for hue
    [colors.normal]
    black   = '#${p.raisedBlack}'
    red     = '#${p.subtleBorder}'
    green   = '#${p.mutedText}'
    yellow  = '#${p.secondaryText}'
    blue    = '#${p.accent}'
    magenta = '#${p.foreground}'
    cyan    = '#${p.accent}'
    white   = '#${p.secondaryText}'

    # Bright colors - the upper half of the ladder, for emphasis
    [colors.bright]
    black   = '#${p.subtleBorder}'
    red     = '#${p.mutedText}'
    green   = '#${p.hot}'
    yellow  = '#${p.accent}'
    blue    = '#${p.bright}'
    magenta = '#${p.foreground}'
    cyan    = '#${p.foreground}'
    white   = '#${p.foreground}'

    # Dim colors - the lower half of the ladder
    [colors.dim]
    black   = '#${p.deepSurface}'
    red     = '#${p.deepSurface}'
    green   = '#${p.subtleBorder}'
    yellow  = '#${p.mutedText}'
    blue    = '#${p.mutedText}'
    magenta = '#${p.secondaryText}'
    cyan    = '#${p.mutedText}'
    white   = '#${p.secondaryText}'

    # Vi mode colors
    [colors.vi_mode_cursor]
    text = '#${p.background}'
    cursor = '#${p.foreground}'

    # Search colors
    [colors.search]
    [colors.search.matches]
    foreground = '#${p.background}'
    background = '#${p.accent}'
    [colors.search.focused_match]
    foreground = '#${p.background}'
    background = '#${p.foreground}'

    # Line indicator colors
    [colors.line_indicator]
    foreground = '#${p.foreground}'
    background = '#${p.background}'

    # Footer bar (used in vi mode)
    [colors.footer_bar]
    foreground = '#${p.foreground}'
    background = '#${p.deepSurface}'
  '';

  # Geometry, font, and cursor behaviour are palette-independent.
  darkChrome = ''

    # Window settings
    [window]
    padding.x = 8
    padding.y = 8
    decorations = "full"

    # Font settings
    [font]
    size = 12.0
    normal.family = "Hack Nerd Font"
    normal.style = "Regular"
    bold.family = "Hack Nerd Font"
    bold.style = "Bold"
    italic.family = "Hack Nerd Font"
    italic.style = "Italic"
    bold_italic.family = "Hack Nerd Font"
    bold_italic.style = "Bold Italic"

    # Cursor settings
    [cursor]
    style.shape = "Block"
    style.blinking = "On"
    # blink_interval = 500
    blink_timeout = 0
    unfocused_hollow = true

    # Selection settings
    [selection]
    save_to_clipboard = true
  '';

  mkDarkConfig = p: mkDarkTheme p + darkChrome;
in
{
  programs.alacritty = {
    enable = true;
    settings = {
      general.import = [ "~/.config/alacritty/current.toml" ];

      keyboard.bindings = [
        {
          key = "1";
          mods = "Control";
          chars = "\\u001b[49;5u"; # CSI-u Ctrl+1 for tmux scratch note split
        }
        {
          key = "1";
          mods = "Control|Shift";
          chars = "\\u001b[49;6u"; # CSI-u Ctrl+Shift+1 for tmux scratch note split
        }
        {
          key = "Return";
          mods = "Alt|Shift";
          chars = "\\u001b[21;2~"; # Shift+F10 for tmux vertical split
        }
        {
          key = "Return";
          mods = "Control";
          chars = "\\u001b[13;5u"; # Kitty protocol Ctrl+Enter for multi-line input
        }
        {
          key = "Return";
          mods = "Shift";
          chars = "\\u001b[13;2u"; # CSI-u Shift+Enter for Codex multiline input
        }
        {
          key = "Return";
          mods = "Alt";
          # CSI-u Alt+Enter for herdr's split_vertical (dotfiles/herdr/config.toml).
          # Without this, Alacritty falls back to legacy ESC-then-Return encoding,
          # which forces herdr to buffer the lone ESC and guess whether a second
          # byte is coming. Over mosh to Home, network latency can delay that
          # second byte past herdr's internal guess-timeout, so the chord splits
          # into a bare Escape plus an ordinary Enter and the binding never fires
          # (confirmed via a "flushing lone escape after input timeout" warning in
          # herdr-server.log). A CSI-u sequence arrives as one atomic escape
          # sequence, so no guessing is needed.
          chars = "\\u001b[13;3u";
        }
        {
          key = "Insert";
          mods = "Shift";
          action = "Paste";
        }
        {
          key = "V";
          mods = "Control|Shift";
          action = "Paste";
        }
      ];

      window.dynamic_padding = true;
    };
  };

  # Theme files for darkman switching
  home.file = {
    # The theme the dark-mode hook links to: whichever profile is active.
    ".config/alacritty/themes/dark.toml".text = mkDarkConfig palettes.active;

    ".config/alacritty/themes/light.toml".text = ''
      # E-Ink Theme for Alacritty Terminal
      # Brown-black CRT glass and white theme optimized for e-ink displays

      [colors]
      # Default colors
      [colors.primary]
      background = '#FFFFFF'  # Pure white background
      foreground = '#000000'  # Brown-black CRT glass text

      # Cursor colors
      [colors.cursor]
      text = '#FFFFFF'    # White text when cursor is over it
      cursor = '#000000'  # Black cursor block

      # Selection colors (inverted for visibility)
      [colors.selection]
      text = '#FFFFFF'
      background = '#000000'

      # Normal colors - all mapped to black/white for e-ink
      [colors.normal]
      black   = '#000000'
      red     = '#000000'
      green   = '#000000'
      yellow  = '#000000'
      blue    = '#000000'
      magenta = '#000000'
      cyan    = '#000000'
      white   = '#FFFFFF'

      # Bright colors - using same as normal for consistency
      [colors.bright]
      black   = '#808080'
      red     = '#808080'
      green   = '#808080'
      yellow  = '#808080'
      blue    = '#808080'
      magenta = '#808080'
      cyan    = '#808080'
      white   = '#FFFFFF'

      # Dim colors - using same as normal for e-ink
      [colors.dim]
      black   = '#000000'
      red     = '#000000'
      green   = '#000000'
      yellow  = '#000000'
      blue    = '#000000'
      magenta = '#000000'
      cyan    = '#000000'
      white   = '#FFFFFF'

      # Vi mode colors
      [colors.vi_mode_cursor]
      text = '#FFFFFF'
      cursor = '#000000'

      # Search colors
      [colors.search]
      [colors.search.matches]
      foreground = '#FFFFFF'
      background = '#000000'

      [colors.search.focused_match]
      foreground = '#000000'
      background = '#FFFFFF'

      # Line indicator colors
      [colors.line_indicator]
      foreground = '#000000'
      background = '#FFFFFF'

      # Footer bar (used in vi mode)
      [colors.footer_bar]
      foreground = '#000000'
      background = '#FFFFFF'

      # Window settings for better e-ink display
      [window]
      padding.x = 10
      padding.y = 10
      decorations = "full"

      # Font settings optimized for e-ink
      [font]
      size = 11.0
      normal.family = "Hack Nerd Font"
      normal.style = "Regular"
      bold.family = "Hack Nerd Font"
      bold.style = "Bold"
      italic.family = "Hack Nerd Font"
      italic.style = "Italic"
      bold_italic.family = "Hack Nerd Font"
      bold_italic.style = "Bold Italic"

      # Selection settings
      [selection]
      save_to_clipboard = true
    '';
  }
  # Every profile is also written under its own name so two phosphors can be
  # compared live: relink ~/.config/alacritty/current.toml at one of these and
  # open a new window. A dark/light switch puts the active profile back.
  // lib.mapAttrs' (
    name: p: lib.nameValuePair ".config/alacritty/themes/dark-${name}.toml" { text = mkDarkConfig p; }
  ) (palettes.profiles // palettes.previewProfiles);
}
