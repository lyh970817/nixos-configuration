# Codex CLI syntax theme
#
# Codex paints its own chrome -- borders, message text, the composer, approval
# dialogs -- with ANSI *indices* rather than RGB, deliberately: its style guide
# forbids custom colours so the TUI inherits whatever palette the terminal is
# carrying. So the chrome already follows the phosphor ladder through
# programs/foot.nix with nothing configured here.
#
# What it does not inherit is the syntax highlighter. `[tui] theme` selects a
# TextMate .tmTheme -- by default one of the bundled `bat` themes, every one of
# which hardcodes its own RGB and so fights a single-phosphor palette on sight.
# The theme below replaces it with one generated from ../palettes.nix, so code
# blocks are rendered in the same ladder as everything else and follow a
# phosphor swap without being retuned.
#
# It reaches two other surfaces:
#   * diff line backgrounds, taken from markup.inserted / markup.deleted;
#   * the status line, when `[tui] status_line_use_colors` is true (the
#     default), which maps each segment onto a TextMate scope.
# Both are covered below.
#
# The selection is pinned by the codex config reconciler in
# mutable-configs.nix, which enforces `[tui] theme` on every activation --
# otherwise a stray `/theme` would silently strand Codex on a bat theme.
#
# Only the dark profile is generated. Light mode is a single flat black-on-
# white scheme with no ladder to map scopes onto, and `[tui] theme` is one
# static config key with no per-session switch, so there is nothing useful to
# point it at; in light mode Codex falls back to its adaptive default.
{ ... }:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;

  themeName = "vt220-phosphor";

  # Syntax highlighting has no hue to work with here, so the usual
  # "keywords are purple, strings are green" vocabulary collapses into the one
  # axis the palette has: how much a token stands off the glass. Structure --
  # keywords, type and function names, tags -- takes the `bright` rung so the
  # shape of the code reads at a glance; literals sit a rung lower on `accent`;
  # plain identifiers stay at `foreground`; comments and punctuation recede to
  # `secondaryText`. `hot` is held back for genuinely invalid syntax, which is
  # the only thing that should be the brightest object on screen.
  scope = name: colour: extra: ''
    <dict>
      <key>scope</key>
      <string>${name}</string>
      <key>settings</key>
      <dict>
        <key>foreground</key>
        <string>#${colour}</string>${extra}
      </dict>
    </dict>'';

  fontStyle = style: ''

    <key>fontStyle</key>
    <string>${style}</string>'';

  background = colour: ''

    <key>background</key>
    <string>#${colour}</string>'';

  tmTheme = ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key>
      <string>VT220 Phosphor</string>
      <key>settings</key>
      <array>
        <dict>
          <key>settings</key>
          <dict>
            <key>background</key>
            <string>#${p.background}</string>
            <key>foreground</key>
            <string>#${p.foreground}</string>
            <key>caret</key>
            <string>#${p.accent}</string>
            <key>lineHighlight</key>
            <string>#${p.deepSurface}</string>
            <key>selection</key>
            <string>#${p.accent}</string>
          </dict>
        </dict>
    ${scope "comment, punctuation.definition.comment" p.secondaryText (fontStyle "italic")}
    ${scope "punctuation, meta.brace, punctuation.separator, punctuation.terminator" p.secondaryText ""}
    ${scope "string, string.quoted, constant.character, constant.character.escape" p.accent ""}
    ${scope "constant.numeric, constant.language, constant.other" p.accent ""}
    ${scope "entity.other.attribute-name" p.accent ""}
    ${scope "variable, variable.other, variable.parameter, meta.definition.variable" p.foreground ""}
    ${scope "keyword, keyword.control, keyword.operator, storage, storage.type, storage.modifier"
      p.bright
      ""
    }
    ${scope "entity.name.function, support.function, meta.function-call" p.bright ""}
    ${scope
      "entity.name.type, entity.name.class, entity.other.inherited-class, support.type, support.class"
      p.bright
      ""
    }
    ${scope "entity.name.tag" p.bright ""}
    ${scope "invalid, invalid.illegal, invalid.deprecated" p.hot (fontStyle "bold")}
    ${scope "markup.heading, entity.name.section" p.bright (fontStyle "bold")}
    ${scope "markup.underline.link, markup.underline" p.accent (fontStyle "underline")}
    ${scope "markup.bold" p.foreground (fontStyle "bold")}
    ${scope "markup.italic" p.foreground (fontStyle "italic")}
    ${scope "meta.diff, meta.diff.header, meta.diff.range" p.secondaryText ""}
    ${scope "markup.changed, markup.changed.diff" p.accent ""}
    ${
      # A diff has no red and green to spend either. An added line is lifted
      # onto `bright` over the raised black that ANSI black already uses for
      # panel fills; a removed line recedes to `secondaryText` over the
      # deeper surface. Direction reads as intensity, not hue.
      scope "markup.inserted, markup.inserted.diff" p.bright (background p.raisedBlack)
    }
    ${scope "markup.deleted, markup.deleted.diff" p.secondaryText (background p.deepSurface)}
      </array>
    </dict>
    </plist>
  '';
in
{
  home.file.".codex/themes/${themeName}.tmTheme".text = tmTheme;
}
