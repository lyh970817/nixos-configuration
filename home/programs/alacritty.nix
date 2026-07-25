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
      # Matrix-Style Green Theme for Alacritty Terminal
      # Black background with green gradient colors

      [colors]
      # Default colors
      [colors.primary]
      background = '#000000'  # Pure black background
      foreground = '#4AB34D'  # Bright Apple green text for readability

      # Cursor colors
      [colors.cursor]
      text = '#000000'        # Black text when cursor is over it
      cursor = '#3CA23F'      # American Green cursor block

      # Selection colors
      [colors.selection]
      text = '#000000'
      background = '#2E9031'  # Wageningen Green highlight

      # Normal colors - using green gradient
      [colors.normal]
      black   = '#0C3A0E'  # Dark green — lifted off pure-black bg so ANSI-selected rows are visible
      red     = '#126D15'  # Verse Green
      green   = '#207F23'  # Web Forest Green
      yellow  = '#2E9031'  # Wageningen Green
      blue    = '#3CA23F'  # American Green
      magenta = '#4AB34D'  # Apple (brightest)
      cyan    = '#3CA23F'  # American Green
      white   = '#2E9031'  # Wageningen Green — receded below the #4AB34D foreground so SGR-37 secondary text (menu descriptions, hints) reads as secondary

      # Bright colors - using lighter greens for emphasis
      [colors.bright]
      black   = '#126D15'  # Verse Green
      red     = '#207F23'  # Web Forest Green
      green   = '#7CDC7F'  # Light green — lifted above the #4AB34D foreground so bright-green emphasis (e.g. selected menu entries) is distinguishable
      yellow  = '#3CA23F'  # American Green
      blue    = '#63C766'  # Soft light green — above the #4AB34D foreground but below bright green, so fuzzy-match fragments read as accents rather than glare
      magenta = '#4AB34D'  # Apple
      cyan    = '#4AB34D'  # Apple
      white   = '#4AB34D'  # Apple (brightest)

      # Dim colors - using darker greens
      [colors.dim]
      black   = '#045C07'  # Deep Green (darkest)
      red     = '#045C07'  # Deep Green
      green   = '#126D15'  # Verse Green
      yellow  = '#207F23'  # Web Forest Green
      blue    = '#207F23'  # Web Forest Green
      magenta = '#2E9031'  # Wageningen Green
      cyan    = '#207F23'  # Web Forest Green
      white   = '#2E9031'  # Wageningen Green

      # Vi mode colors
      [colors.vi_mode_cursor]
      text = '#000000'
      cursor = '#4AB34D'

      # Search colors
      [colors.search]
      [colors.search.matches]
      foreground = '#000000'
      background = '#3CA23F'  # American Green
      [colors.search.focused_match]
      foreground = '#000000'
      background = '#4AB34D'  # Apple (brightest for focus)

      # Line indicator colors
      [colors.line_indicator]
      foreground = '#4AB34D'
      background = '#000000'

      # Footer bar (used in vi mode)
      [colors.footer_bar]
      foreground = '#4AB34D'
      background = '#045C07'  # Deep Green for contrast

      # Window settings
      [window]
      padding.x = 10
      padding.y = 10
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
      # Pure black and white theme optimized for e-ink displays

      [colors]
      # Default colors
      [colors.primary]
      background = '#FFFFFF'  # Pure white background
      foreground = '#000000'  # Pure black text

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
