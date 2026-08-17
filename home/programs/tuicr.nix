{
  pkgs,
  ...
}:

let
  p = (import ../palettes.nix).active;

  mkTheme = c: syntaxTheme: ''
    panel_bg = "#${c.panelBg}"
    bg_highlight = "#${c.bgHighlight}"
    fg_primary = "#${c.fgPrimary}"
    fg_secondary = "#${c.fgSecondary}"
    fg_dim = "#${c.fgDim}"

    diff_add = "#${c.diffAdd}"
    diff_add_bg = "#${c.diffAddBg}"
    diff_del = "#${c.diffDel}"
    diff_del_bg = "#${c.diffDelBg}"
    diff_context = "#${c.fgPrimary}"
    diff_hunk_header = "#${c.accent}"
    expanded_context_fg = "#${c.fgDim}"
    syntax_add_bg = "#${c.diffAddBg}"
    syntax_del_bg = "#${c.diffDelBg}"
    syntax_theme = "${syntaxTheme}"

    file_added = "#${c.diffAdd}"
    file_modified = "#${c.accent}"
    file_deleted = "#${c.diffDel}"
    file_renamed = "#${c.fgPrimary}"
    reviewed = "#${c.diffAdd}"
    pending = "#${c.accent}"

    comment_note = "#${c.fgSecondary}"
    comment_suggestion = "#${c.accent}"
    comment_issue = "#${c.diffDel}"
    comment_praise = "#${c.diffAdd}"
    border_focused = "#${c.accent}"
    border_unfocused = "#${c.border}"
    status_bar_bg = "#${c.statusBg}"
    cursor_color = "#${c.cursor}"
    cursor_line_bg = "#${c.bgHighlight}"
    branch_name = "#${c.accent}"
    help_indicator = "#${c.fgDim}"

    message_info_fg = "#${c.messageFg}"
    message_info_bg = "#${c.fgSecondary}"
    message_warning_fg = "#${c.messageFg}"
    message_warning_bg = "#${c.accent}"
    message_error_fg = "#${c.messageFg}"
    message_error_bg = "#${c.diffDel}"
    update_badge_fg = "#${c.messageFg}"
    update_badge_bg = "#${c.accent}"
    mode_fg = "#${c.messageFg}"
    mode_bg = "#${c.accent}"
  '';

  mkSyntaxTheme = name: c: ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key><string>${name}</string>
      <key>settings</key>
      <array>
        <dict><key>settings</key><dict>
          <key>background</key><string>#${c.background}</string>
          <key>foreground</key><string>#${c.foreground}</string>
          <key>caret</key><string>#${c.accent}</string>
          <key>selection</key><string>#${c.selection}</string>
          <key>lineHighlight</key><string>#${c.lineHighlight}</string>
        </dict></dict>
        <dict><key>scope</key><string>comment, punctuation.definition.comment</string><key>settings</key><dict><key>foreground</key><string>#${c.comment}</string><key>fontStyle</key><string>italic</string></dict></dict>
        <dict><key>scope</key><string>punctuation, meta.brace, punctuation.separator, punctuation.terminator</string><key>settings</key><dict><key>foreground</key><string>#${c.comment}</string></dict></dict>
        <dict><key>scope</key><string>string, constant.character, constant.numeric, constant.language</string><key>settings</key><dict><key>foreground</key><string>#${c.literal}</string></dict></dict>
        <dict><key>scope</key><string>keyword, storage, entity.name.function, support.function, entity.name.type, support.type, entity.name.tag</string><key>settings</key><dict><key>foreground</key><string>#${c.structure}</string></dict></dict>
        <dict><key>scope</key><string>variable, variable.parameter, support.variable</string><key>settings</key><dict><key>foreground</key><string>#${c.foreground}</string></dict></dict>
        <dict><key>scope</key><string>invalid, invalid.illegal</string><key>settings</key><dict><key>foreground</key><string>#${c.invalidFg}</string><key>background</key><string>#${c.invalidBg}</string><key>fontStyle</key><string>bold</string></dict></dict>
      </array>
    </dict>
    </plist>
  '';

  dark = {
    panelBg = p.background;
    bgHighlight = p.deepSurface;
    fgPrimary = p.foreground;
    fgSecondary = p.secondaryText;
    fgDim = p.mutedText;
    diffAdd = p.bright;
    diffAddBg = p.raisedBlack;
    diffDel = p.secondaryText;
    diffDelBg = p.deepSurface;
    accent = p.accent;
    border = p.subtleBorder;
    statusBg = p.deepSurface;
    cursor = p.hot;
    messageFg = p.background;
  };

  light = {
    panelBg = "FFFFFF";
    bgHighlight = "E8E8E8";
    fgPrimary = "000000";
    fgSecondary = "303030";
    fgDim = "686868";
    diffAdd = "000000";
    diffAddBg = "E2E2E2";
    diffDel = "686868";
    diffDelBg = "F2F2F2";
    accent = "000000";
    border = "A0A0A0";
    statusBg = "E8E8E8";
    cursor = "000000";
    messageFg = "FFFFFF";
  };
in
{
  home.packages = [ pkgs.tuicr ];

  xdg.configFile = {
    "tuicr/config.toml".text = ''
      appearance = "system"
      theme_dark = "vt220-phosphor"
      theme_light = "eink"
    '';
    "tuicr/themes/vt220-phosphor.toml".text = mkTheme dark "vt220-phosphor.tmTheme";
    "tuicr/themes/vt220-phosphor.tmTheme".text = mkSyntaxTheme "VT220 Phosphor" {
      background = p.background;
      foreground = p.foreground;
      accent = p.accent;
      selection = p.accent;
      lineHighlight = p.deepSurface;
      comment = p.secondaryText;
      literal = p.accent;
      structure = p.bright;
      invalidFg = p.background;
      invalidBg = p.hot;
    };
    "tuicr/themes/eink.toml".text = mkTheme light "eink.tmTheme";
    "tuicr/themes/eink.tmTheme".text = mkSyntaxTheme "E-ink" {
      background = "FFFFFF";
      foreground = "000000";
      accent = "000000";
      selection = "D0D0D0";
      lineHighlight = "E8E8E8";
      comment = "686868";
      literal = "303030";
      structure = "000000";
      invalidFg = "FFFFFF";
      invalidBg = "000000";
    };
  };
}
