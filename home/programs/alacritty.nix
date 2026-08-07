# Alacritty Terminal Configuration
# Managed by home-manager
# Original: ~/.config/alacritty/
# Theme switching handled by darkman hooks (symlinks to current.toml)
{ config, pkgs, ... }:

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
    ".config/alacritty/themes/dark.toml".text = ''
      # VT220 Amber Theme for Alacritty Terminal
      # Black background with amber intensity ladder colors

      [colors]
      # Default colors
      [colors.primary]
      background = '#080705'  # Brown-black CRT glass background
      foreground = '#D99B32'  # Bright amber text for readability

      # Cursor colors
      [colors.cursor]
      text = '#080705'        # Black text when cursor is over it
      cursor = '#BE842A'      # Accent amber cursor block

      # Selection colors
      [colors.selection]
      text = '#080705'
      background = '#9B6D24'  # Secondary amber highlight

      # Normal colors - using amber intensity ladder
      [colors.normal]
      black   = '#110E08'  # Dark amber — lifted off pure-black bg so ANSI-selected rows are visible
      red     = '#2A2011'  # Subtle border
      green   = '#6E501D'  # Muted amber
      yellow  = '#9B6D24'  # Secondary amber
      blue    = '#BE842A'  # Accent amber
      magenta = '#D99B32'  # Warm amber (brightest)
      cyan    = '#BE842A'  # Accent amber
      white   = '#9B6D24'  # Secondary amber — receded below the #D99B32 foreground so SGR-37 secondary text (menu descriptions, hints) reads as secondary

      # Bright colors - using lighter ambers for emphasis
      [colors.bright]
      black   = '#2A2011'  # Subtle border
      red     = '#6E501D'  # Muted amber
      green   = '#FFD064'  # Light amber — lifted above the #D99B32 foreground so bright-amber emphasis (e.g. selected menu entries) is distinguishable
      yellow  = '#BE842A'  # Accent amber
      blue    = '#EDB144'  # Soft light amber — above the #D99B32 foreground but below bright amber, so fuzzy-match fragments read as accents rather than glare
      magenta = '#D99B32'  # Warm amber
      cyan    = '#D99B32'  # Warm amber
      white   = '#D99B32'  # Warm amber (brightest)

      # Dim colors - using darker ambers
      [colors.dim]
      black   = '#0C0A06'  # Deep surface (darkest)
      red     = '#0C0A06'  # Deep surface
      green   = '#2A2011'  # Subtle border
      yellow  = '#6E501D'  # Muted amber
      blue    = '#6E501D'  # Muted amber
      magenta = '#9B6D24'  # Secondary amber
      cyan    = '#6E501D'  # Muted amber
      white   = '#9B6D24'  # Secondary amber

      # Vi mode colors
      [colors.vi_mode_cursor]
      text = '#080705'
      cursor = '#D99B32'

      # Search colors
      [colors.search]
      [colors.search.matches]
      foreground = '#080705'
      background = '#BE842A'  # Accent amber
      [colors.search.focused_match]
      foreground = '#080705'
      background = '#D99B32'  # Warm amber (brightest for focus)

      # Line indicator colors
      [colors.line_indicator]
      foreground = '#D99B32'
      background = '#080705'

      # Footer bar (used in vi mode)
      [colors.footer_bar]
      foreground = '#D99B32'
      background = '#0C0A06'  # Deep surface for contrast

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
  };
}
