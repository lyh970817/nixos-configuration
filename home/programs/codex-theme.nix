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
# The mutable config keeps a dark fallback for direct store-path invocations;
# the user-facing wrapper below supplies a process-local `-c tui.theme=...`
# override from THEME_MODE. That override never rewrites config.toml, so light
# and dark Codex sessions can run concurrently without racing over one setting.
{ pkgs, ... }:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;

  darkThemeName = "vt220-phosphor";
  lightThemeName = "eink";

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

  mkTmTheme = c: ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>name</key>
      <string>${c.displayName}</string>
      <key>settings</key>
      <array>
        <dict>
          <key>settings</key>
          <dict>
            <key>background</key>
            <string>#${c.background}</string>
            <key>foreground</key>
            <string>#${c.foreground}</string>
            <key>caret</key>
            <string>#${c.accent}</string>
            <key>lineHighlight</key>
            <string>#${c.deepSurface}</string>
            <key>selection</key>
            <string>#${c.selection}</string>
          </dict>
        </dict>
    ${scope "comment, punctuation.definition.comment" c.secondaryText (fontStyle "italic")}
    ${scope "punctuation, meta.brace, punctuation.separator, punctuation.terminator" c.secondaryText ""}
    ${scope "string, string.quoted, constant.character, constant.character.escape" c.accent ""}
    ${scope "constant.numeric, constant.language, constant.other" c.accent ""}
    ${scope "entity.other.attribute-name" c.accent ""}
    ${scope "variable, variable.other, variable.parameter, meta.definition.variable" c.foreground ""}
    ${scope "keyword, keyword.control, keyword.operator, storage, storage.type, storage.modifier"
      c.bright
      ""
    }
    ${scope "entity.name.function, support.function, meta.function-call" c.bright ""}
    ${scope
      "entity.name.type, entity.name.class, entity.other.inherited-class, support.type, support.class"
      c.bright
      ""
    }
    ${scope "entity.name.tag" c.bright ""}
    ${scope "invalid, invalid.illegal, invalid.deprecated" c.invalid (fontStyle "bold")}
    ${scope "markup.heading, entity.name.section" c.bright (fontStyle "bold")}
    ${scope "markup.underline.link, markup.underline" c.accent (fontStyle "underline")}
    ${scope "markup.bold" c.foreground (fontStyle "bold")}
    ${scope "markup.italic" c.foreground (fontStyle "italic")}
    ${scope "meta.diff, meta.diff.header, meta.diff.range" c.secondaryText ""}
    ${scope "markup.changed, markup.changed.diff" c.accent ""}
    ${scope "markup.inserted, markup.inserted.diff" c.inserted (background c.insertedBackground)}
    ${scope "markup.deleted, markup.deleted.diff" c.deleted (background c.deletedBackground)}
      </array>
    </dict>
    </plist>
  '';

  darkTheme = mkTmTheme (
    p
    // {
      displayName = "VT220 Phosphor";
      selection = p.accent;
      invalid = p.hot;
      inserted = p.bright;
      insertedBackground = p.raisedBlack;
      deleted = p.secondaryText;
      deletedBackground = p.deepSurface;
    }
  );

  lightTheme = mkTmTheme {
    displayName = "E-ink";
    background = "FFFFFF";
    foreground = "000000";
    accent = "303030";
    secondaryText = "686868";
    bright = "000000";
    deepSurface = "E8E8E8";
    selection = "D0D0D0";
    invalid = "000000";
    inserted = "000000";
    insertedBackground = "E2E2E2";
    deleted = "686868";
    deletedBackground = "F2F2F2";
  };

  codexWrapped = pkgs.symlinkJoin {
    name = "codex-themed";
    paths = [ pkgs.codex ];
    postBuild = ''
      rm "$out/bin/codex"
      cat > "$out/bin/codex" <<'WRAPPER'
      #!${pkgs.runtimeShell}
      mode="''${THEME_MODE:-}"
      if [ -z "$mode" ]; then
        case "$(${pkgs.coreutils}/bin/readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
          *dark.lua) mode=dark ;;
          *light.lua) mode=light ;;
          *)
            echo "codex: cannot determine the terminal session theme" >&2
            exit 1
            ;;
        esac
      fi

      case "$mode" in
        dark) theme="${darkThemeName}" ;;
        light) theme="${lightThemeName}" ;;
        *)
          echo "codex: invalid THEME_MODE: $mode" >&2
          exit 1
          ;;
      esac

      exec ${pkgs.codex}/bin/codex -c "tui.theme=\"$theme\"" "$@"
      WRAPPER
      chmod +x "$out/bin/codex"
    '';
  };
in
{
  home.packages = [ codexWrapped ];

  home.file = {
    ".codex/themes/${darkThemeName}.tmTheme".text = darkTheme;
    ".codex/themes/${lightThemeName}.tmTheme".text = lightTheme;
  };
}
