# Yazi monochrome flavors
#
# Both desktop modes use a single-hue hierarchy: phosphor luminance on a dark
# ground and grayscale luminance on the inverse e-ink ground. Their colors and
# emphasis choices remain separate below, while one renderer owns the Yazi
# schema, file rules, icon categories, and syntect scopes for both flavors.
{ lib, ... }:

let
  palettes = import ../palettes.nix;

  darkPalette = lib.mapAttrs (_: value: "#${value}") palettes.active;
  lightPalette = {
    black = "#000000";
    gray20 = "#D0D0D0";
    gray25 = "#C0C0C0";
    gray30 = "#B0B0B0";
    gray35 = "#A0A0A0";
    gray40 = "#909090";
    gray50 = "#808080";
    gray55 = "#707070";
    gray60 = "#606060";
    gray70 = "#505050";
    gray75 = "#404040";
    surface = "#F0F0F0";
    surfaceStrong = "#E0E0E0";
    white = "#FFFFFF";
  };

  # Explicit mode maps preserve the distinctions that are not simple palette
  # substitutions. For example, e-ink uses different grays for a hover, a
  # search hit, and a progress fill even where dark mode uses one phosphor rung.
  darkChrome =
    let
      c = darkPalette;
    in
    {
      mgr = {
        cwd = {
          fg = c.foreground;
          bg = c.background;
          bold = true;
        };
        hovered = {
          fg = c.background;
          bg = c.accent;
          bold = true;
        };
        previewHovered = {
          fg = c.background;
          bg = c.secondaryText;
        };
        findKeyword = {
          fg = c.background;
          bg = c.foreground;
          bold = true;
        };
        findPosition = {
          fg = c.accent;
        };
        markerCopied = {
          fg = c.accent;
          bg = c.accent;
        };
        markerCut = {
          fg = c.secondaryText;
          bg = c.secondaryText;
        };
        markerMarked = {
          fg = c.foreground;
          bg = c.foreground;
        };
        markerSelected = {
          fg = c.foreground;
          bg = c.foreground;
        };
        countCopied = {
          fg = c.foreground;
          bg = c.deepSurface;
        };
        countCut = {
          fg = c.foreground;
          bg = c.subtleBorder;
        };
        countSelected = {
          fg = c.background;
          bg = c.accent;
        };
        border = {
          fg = c.foreground;
        };
      };
      tabs = {
        active = {
          fg = c.foreground;
          bg = c.background;
          bold = true;
        };
        inactive = {
          fg = c.mutedText;
          bg = c.deepSurface;
        };
      };
      mode = {
        normalMain = {
          fg = c.foreground;
          bg = c.background;
          bold = true;
        };
        normalAlt = {
          fg = c.accent;
          bg = c.background;
        };
        selectMain = {
          fg = c.background;
          bg = c.foreground;
          bold = true;
        };
        selectAlt = {
          fg = c.background;
          bg = c.accent;
        };
        unsetMain = {
          fg = c.mutedText;
          bg = c.deepSurface;
        };
        unsetAlt = {
          fg = c.secondaryText;
          bg = c.deepSurface;
        };
      };
      status = {
        overall = {
          fg = c.foreground;
          bg = c.background;
        };
        permType = {
          fg = c.foreground;
          bold = true;
        };
        permRead = {
          fg = c.accent;
        };
        permWrite = {
          fg = c.secondaryText;
        };
        permExec = {
          fg = c.foreground;
          bold = true;
        };
        permSep = {
          fg = c.mutedText;
        };
        progressLabel = {
          fg = c.foreground;
          bold = true;
        };
        progressNormal = {
          fg = c.background;
          bg = c.accent;
        };
        progressError = {
          fg = c.background;
          bg = c.foreground;
          bold = true;
        };
      };
      which = {
        mask = {
          bg = c.deepSurface;
        };
        candidate = {
          fg = c.foreground;
          bold = true;
        };
        rest = {
          fg = c.accent;
        };
        description = {
          fg = c.accent;
        };
        separator = {
          fg = c.mutedText;
        };
      };
      confirm = {
        border = {
          fg = c.foreground;
        };
        title = {
          fg = c.foreground;
          bold = true;
        };
        content = {
          fg = c.foreground;
        };
        list = {
          fg = c.accent;
        };
        yes = {
          fg = c.foreground;
          bg = c.background;
          bold = true;
        };
        no = {
          fg = c.foreground;
          bg = c.background;
        };
      };
      spot = {
        border = {
          fg = c.mutedText;
        };
        title = {
          fg = c.foreground;
          bold = true;
        };
        column = {
          fg = c.background;
          bg = c.secondaryText;
        };
        cell = {
          fg = c.background;
          bg = c.accent;
        };
      };
      notify = {
        info = {
          fg = c.foreground;
          bold = true;
        };
        warn = {
          fg = c.foreground;
          bg = c.subtleBorder;
          bold = true;
        };
        error = {
          fg = c.background;
          bg = c.foreground;
          bold = true;
        };
      };
      pick = {
        border = {
          fg = c.mutedText;
        };
        active = {
          fg = c.background;
          bg = c.accent;
          bold = true;
        };
        inactive = {
          fg = c.secondaryText;
        };
      };
      input = {
        border = {
          fg = c.foreground;
        };
        title = {
          fg = c.foreground;
          bold = true;
        };
        value = {
          fg = c.foreground;
        };
        selected = {
          fg = c.background;
          bg = c.accent;
        };
      };
      completion = {
        border = {
          fg = c.mutedText;
        };
        active = {
          fg = c.background;
          bg = c.accent;
          bold = true;
        };
        inactive = {
          fg = c.secondaryText;
        };
      };
      tasks = {
        border = {
          fg = c.mutedText;
        };
        title = {
          fg = c.foreground;
          bold = true;
        };
        hovered = {
          fg = c.background;
          bg = c.secondaryText;
        };
      };
      help = {
        on = {
          fg = c.foreground;
          bold = true;
        };
        run = {
          fg = c.accent;
        };
        description = {
          fg = c.secondaryText;
        };
        hovered = {
          fg = c.background;
          bg = c.accent;
        };
        footer = {
          fg = c.mutedText;
          bg = c.deepSurface;
        };
      };
      filetype = {
        directory = {
          fg = c.foreground;
          bold = true;
        };
        executable = {
          fg = c.accent;
          bold = true;
        };
        archive = {
          fg = c.secondaryText;
        };
        document = {
          fg = c.accent;
        };
        image = {
          fg = c.secondaryText;
        };
        media = {
          fg = c.mutedText;
        };
        text = {
          fg = c.foreground;
        };
        code = {
          fg = c.foreground;
        };
        config = {
          fg = c.secondaryText;
        };
        hidden = {
          # Hidden entries still need to remain comfortably legible; their
          # leading dot already communicates the secondary status.
          fg = c.foreground;
        };
        link = {
          fg = c.accent;
          italic = true;
        };
        orphan = {
          fg = c.foreground;
          bg = c.deepSurface;
        };
        empty = {
          fg = c.foreground;
        };
        fallback = {
          fg = c.secondaryText;
        };
      };
      directoryIcon = "blue";
    };

  lightChrome =
    let
      c = lightPalette;
    in
    {
      mgr = {
        cwd = {
          fg = c.black;
          bg = c.white;
          bold = true;
        };
        hovered = {
          fg = c.white;
          bg = c.gray75;
          bold = true;
        };
        previewHovered = {
          fg = c.white;
          bg = c.gray70;
        };
        findKeyword = {
          fg = c.black;
          bg = c.gray25;
          bold = true;
        };
        findPosition = {
          fg = c.gray50;
        };
        markerCopied = {
          fg = c.gray50;
          bg = c.gray50;
        };
        markerCut = {
          fg = c.gray30;
          bg = c.gray30;
        };
        markerMarked = {
          fg = c.black;
          bg = c.black;
        };
        markerSelected = {
          fg = c.black;
          bg = c.black;
        };
        countCopied = {
          fg = c.black;
          bg = c.gray20;
        };
        countCut = {
          fg = c.black;
          bg = c.gray30;
        };
        countSelected = {
          fg = c.white;
          bg = c.gray75;
        };
        border = {
          fg = c.black;
        };
      };
      tabs = {
        active = {
          fg = c.black;
          bg = c.white;
          bold = true;
        };
        inactive = {
          fg = c.gray50;
          bg = c.surface;
        };
      };
      mode = {
        normalMain = {
          fg = c.black;
          bg = c.white;
          bold = true;
        };
        normalAlt = {
          fg = c.gray75;
          bg = c.white;
        };
        selectMain = {
          fg = c.white;
          bg = c.black;
          bold = true;
        };
        selectAlt = {
          fg = c.gray25;
          bg = c.black;
        };
        unsetMain = {
          fg = c.gray50;
          bg = c.surface;
        };
        unsetAlt = {
          fg = c.gray35;
          bg = c.surface;
        };
      };
      status = {
        overall = {
          fg = c.black;
          bg = c.white;
        };
        permType = {
          fg = c.black;
          bold = true;
        };
        permRead = {
          fg = c.gray75;
        };
        permWrite = {
          fg = c.gray60;
        };
        permExec = {
          fg = c.black;
          bold = true;
        };
        permSep = {
          fg = c.gray25;
        };
        progressLabel = {
          fg = c.black;
          bold = true;
        };
        progressNormal = {
          fg = c.white;
          bg = c.gray50;
        };
        progressError = {
          fg = c.white;
          bg = c.black;
          bold = true;
        };
      };
      which = {
        mask = {
          bg = c.surfaceStrong;
        };
        candidate = {
          fg = c.black;
          bold = true;
        };
        rest = {
          fg = c.gray75;
        };
        description = {
          fg = c.gray75;
        };
        separator = {
          fg = c.gray50;
        };
      };
      confirm = {
        border = {
          fg = c.black;
        };
        title = {
          fg = c.black;
          bold = true;
        };
        content = {
          fg = c.black;
        };
        list = {
          fg = c.gray75;
        };
        yes = {
          fg = c.black;
          bg = c.white;
          bold = true;
        };
        no = {
          fg = c.black;
          bg = c.white;
        };
      };
      spot = {
        border = {
          fg = c.gray50;
        };
        title = {
          fg = c.black;
          bold = true;
        };
        column = {
          fg = c.white;
          bg = c.gray60;
        };
        cell = {
          fg = c.white;
          bg = c.gray75;
        };
      };
      notify = {
        info = {
          fg = c.black;
          bold = true;
        };
        warn = {
          fg = c.black;
          bg = c.gray20;
          bold = true;
        };
        error = {
          fg = c.white;
          bg = c.black;
          bold = true;
        };
      };
      pick = {
        border = {
          fg = c.gray50;
        };
        active = {
          fg = c.white;
          bg = c.gray75;
          bold = true;
        };
        inactive = {
          fg = c.gray60;
        };
      };
      input = {
        border = {
          fg = c.black;
        };
        title = {
          fg = c.black;
          bold = true;
        };
        value = {
          fg = c.black;
        };
        selected = {
          fg = c.white;
          bg = c.gray50;
        };
      };
      completion = {
        border = {
          fg = c.gray50;
        };
        active = {
          fg = c.white;
          bg = c.gray75;
          bold = true;
        };
        inactive = {
          fg = c.gray60;
        };
      };
      tasks = {
        border = {
          fg = c.gray50;
        };
        title = {
          fg = c.black;
          bold = true;
        };
        hovered = {
          fg = c.white;
          bg = c.gray60;
        };
      };
      help = {
        on = {
          fg = c.black;
          bold = true;
        };
        run = {
          fg = c.gray75;
        };
        description = {
          fg = c.gray60;
        };
        hovered = {
          fg = c.white;
          bg = c.gray50;
        };
        footer = {
          fg = c.gray50;
          bg = c.surface;
        };
      };
      filetype = {
        directory = {
          fg = c.black;
          bold = true;
        };
        executable = {
          fg = c.gray75;
          bold = true;
        };
        archive = {
          fg = c.gray60;
        };
        document = {
          fg = c.gray75;
        };
        image = {
          fg = c.gray70;
        };
        media = {
          fg = c.gray60;
        };
        text = {
          fg = c.black;
        };
        code = {
          fg = c.black;
        };
        config = {
          fg = c.gray55;
        };
        hidden = {
          fg = c.black;
        };
        link = {
          fg = c.gray50;
          italic = true;
        };
        orphan = {
          fg = c.black;
          bg = c.gray20;
        };
        empty = {
          fg = c.black;
        };
        fallback = {
          fg = c.gray60;
        };
      };
      # The light Foot palette maps ANSI blue to black. Yazi 26.5 silently
      # drops hex colors on directory icon conditions, so both flavors use the
      # same ANSI slot and still remain monochrome.
      directoryIcon = "blue";
    };

  darkSyntax =
    let
      c = darkPalette;
    in
    {
      global = {
        background = c.background;
        foreground = c.foreground;
        caret = c.foreground;
        invisibles = c.subtleBorder;
        lineHighlight = c.deepSurface;
        selection = c.mutedText;
        selectionForeground = c.background;
        selectionBorder = c.mutedText;
        findHighlight = c.subtleBorder;
        findHighlightForeground = c.foreground;
        activeGuide = c.subtleBorder;
        guide = c.subtleBorder;
        bracketsForeground = c.foreground;
        bracketsOptions = "underline";
        bracketContentsForeground = c.foreground;
        bracketContentsOptions = "underline";
      };
      styles = {
        comment = {
          foreground = c.secondaryText;
          fontStyle = "italic";
        };
        constant = {
          foreground = c.accent;
          fontStyle = "italic";
        };
        keyword = {
          foreground = c.foreground;
          fontStyle = "bold";
        };
        type = {
          foreground = c.accent;
        };
        function = {
          foreground = c.foreground;
        };
        preprocessor = {
          foreground = c.secondaryText;
        };
        tag = {
          foreground = c.foreground;
          fontStyle = "bold";
        };
        attribute = {
          foreground = c.foreground;
        };
        invalid = {
          foreground = c.foreground;
          background = c.deepSurface;
          fontStyle = "bold";
        };
        todo = {
          foreground = c.background;
          background = c.secondaryText;
          fontStyle = "bold";
        };
        diffAdded = {
          foreground = c.foreground;
        };
        diffRemoved = {
          foreground = c.secondaryText;
        };
        supportClass = {
          foreground = c.accent;
        };
        heading = {
          foreground = c.hot;
          fontStyle = "bold";
        };
        bold = {
          foreground = c.bright;
          fontStyle = "bold";
        };
        italic = {
          foreground = c.foreground;
          fontStyle = "italic";
        };
        raw = {
          foreground = c.accent;
        };
        link = {
          foreground = c.secondaryText;
          fontStyle = "underline";
        };
        list = {
          foreground = c.accent;
        };
        punctuation = {
          foreground = c.mutedText;
        };
      };
    };

  lightSyntax =
    let
      c = lightPalette;
    in
    {
      global = {
        background = c.white;
        foreground = c.black;
        caret = c.black;
        invisibles = c.gray20;
        lineHighlight = "${c.gray20}22";
        selection = c.black;
        selectionForeground = c.white;
        selectionBorder = c.black;
        findHighlight = c.black;
        findHighlightForeground = c.white;
        activeGuide = c.gray20;
        guide = "${c.gray20}44";
        bracketsForeground = c.black;
        bracketsOptions = "underline";
        bracketContentsForeground = c.black;
        bracketContentsOptions = "underline";
      };
      styles = {
        comment = {
          foreground = c.black;
          fontStyle = "italic";
        };
        constant = {
          foreground = c.black;
          fontStyle = "italic";
        };
        keyword = {
          foreground = c.black;
          fontStyle = "bold";
        };
        type = {
          foreground = c.black;
        };
        function = {
          foreground = c.black;
        };
        preprocessor = {
          foreground = c.black;
        };
        tag = {
          foreground = c.black;
          fontStyle = "bold";
        };
        attribute = {
          foreground = c.black;
        };
        invalid = {
          foreground = c.black;
          background = c.gray20;
          fontStyle = "bold";
        };
        todo = {
          foreground = c.white;
          background = c.black;
          fontStyle = "bold";
        };
        diffAdded = {
          foreground = c.black;
        };
        diffRemoved = {
          foreground = c.black;
        };
        supportClass = {
          foreground = c.black;
        };
        heading = {
          foreground = c.black;
          fontStyle = "bold";
        };
        bold = {
          foreground = c.black;
          fontStyle = "bold";
        };
        italic = {
          foreground = c.black;
          fontStyle = "italic";
        };
        raw = {
          foreground = c.gray75;
        };
        link = {
          foreground = c.gray75;
          fontStyle = "underline";
        };
        list = {
          foreground = c.gray60;
        };
        punctuation = {
          foreground = c.gray50;
        };
      };
    };

  themes = {
    dark = {
      name = "VT220 Amber";
      flavor = "vt220-amber";
      description = "active ${palettes.activeName} phosphor profile";
      author = "Based on p7g";
      uuid = "D8D5E82E-3D5B-46B5-B38E-8C841C21347D";
      semanticClass = "theme.dark.vt220-amber";
      chrome = darkChrome;
      syntax = darkSyntax;
    };
    light = {
      name = "E-ink";
      flavor = "eink";
      description = "inverse black, white, and grayscale e-ink profile";
      author = "Based on bow-wob.vim by p7g";
      uuid = "9C8A4F31-6B89-4D9B-A8C1-7F8B8E9D3C21";
      semanticClass = "theme.light.eink";
      chrome = lightChrome;
      syntax = lightSyntax;
    };
  };

  renderTomlValue =
    value:
    if builtins.isBool value then
      (if value then "true" else "false")
    else if builtins.isInt value then
      toString value
    else
      builtins.toJSON value;

  renderInlineTable =
    attrs:
    "{ "
    + lib.concatStringsSep ", " (
      lib.mapAttrsToList (name: value: "${name} = ${renderTomlValue value}") attrs
    )
    + " }";

  renderFileRule = match: style: renderInlineTable (match // style);

  mkFlavor =
    theme:
    let
      s = theme.chrome;
      f = s.filetype;
    in
    ''
      # Yazi ${theme.name} flavor -- UI chrome
      # Generated by home/programs/yazi-theme.nix from the shared monochrome
      # schema and the ${theme.description}. Do not edit the installed copy.

      [mgr]
      cwd = ${renderInlineTable s.mgr.cwd}
      hovered = ${renderInlineTable s.mgr.hovered}
      preview_hovered = ${renderInlineTable s.mgr.previewHovered}
      find_keyword = ${renderInlineTable s.mgr.findKeyword}
      find_position = ${renderInlineTable s.mgr.findPosition}
      marker_copied = ${renderInlineTable s.mgr.markerCopied}
      marker_cut = ${renderInlineTable s.mgr.markerCut}
      marker_marked = ${renderInlineTable s.mgr.markerMarked}
      marker_selected = ${renderInlineTable s.mgr.markerSelected}
      count_copied = ${renderInlineTable s.mgr.countCopied}
      count_cut = ${renderInlineTable s.mgr.countCut}
      count_selected = ${renderInlineTable s.mgr.countSelected}
      border_style = ${renderInlineTable s.mgr.border}
      # An empty value loads tmtheme.xml adjacent to this flavor.
      syntect_theme = ""

      [tabs]
      active = ${renderInlineTable s.tabs.active}
      inactive = ${renderInlineTable s.tabs.inactive}
      sep_inner = { open = "[", close = "]" }
      sep_outer = { open = "", close = "" }

      [mode]
      normal_main = ${renderInlineTable s.mode.normalMain}
      normal_alt = ${renderInlineTable s.mode.normalAlt}
      select_main = ${renderInlineTable s.mode.selectMain}
      select_alt = ${renderInlineTable s.mode.selectAlt}
      unset_main = ${renderInlineTable s.mode.unsetMain}
      unset_alt = ${renderInlineTable s.mode.unsetAlt}

      [status]
      overall = ${renderInlineTable s.status.overall}
      sep_left = { open = "", close = "]" }
      sep_right = { open = "[", close = "" }
      perm_type = ${renderInlineTable s.status.permType}
      perm_read = ${renderInlineTable s.status.permRead}
      perm_write = ${renderInlineTable s.status.permWrite}
      perm_exec = ${renderInlineTable s.status.permExec}
      perm_sep = ${renderInlineTable s.status.permSep}
      progress_label = ${renderInlineTable s.status.progressLabel}
      progress_normal = ${renderInlineTable s.status.progressNormal}
      progress_error = ${renderInlineTable s.status.progressError}

      [which]
      cols = 2
      mask = ${renderInlineTable s.which.mask}
      cand = ${renderInlineTable s.which.candidate}
      rest = ${renderInlineTable s.which.rest}
      desc = ${renderInlineTable s.which.description}
      separator = " → "
      separator_style = ${renderInlineTable s.which.separator}

      [confirm]
      border = ${renderInlineTable s.confirm.border}
      title = ${renderInlineTable s.confirm.title}
      content = ${renderInlineTable s.confirm.content}
      list = ${renderInlineTable s.confirm.list}
      btn_yes = ${renderInlineTable s.confirm.yes}
      btn_no = ${renderInlineTable s.confirm.no}

      [spot]
      border = ${renderInlineTable s.spot.border}
      title = ${renderInlineTable s.spot.title}
      tbl_col = ${renderInlineTable s.spot.column}
      tbl_cell = ${renderInlineTable s.spot.cell}

      [notify]
      title_info = ${renderInlineTable s.notify.info}
      title_warn = ${renderInlineTable s.notify.warn}
      title_error = ${renderInlineTable s.notify.error}

      [pick]
      border = ${renderInlineTable s.pick.border}
      active = ${renderInlineTable s.pick.active}
      inactive = ${renderInlineTable s.pick.inactive}

      [input]
      border = ${renderInlineTable s.input.border}
      title = ${renderInlineTable s.input.title}
      value = ${renderInlineTable s.input.value}
      selected = ${renderInlineTable s.input.selected}

      [cmp]
      border = ${renderInlineTable s.completion.border}
      active = ${renderInlineTable s.completion.active}
      inactive = ${renderInlineTable s.completion.inactive}

      [tasks]
      border = ${renderInlineTable s.tasks.border}
      title = ${renderInlineTable s.tasks.title}
      hovered = ${renderInlineTable s.tasks.hovered}

      [help]
      on = ${renderInlineTable s.help.on}
      run = ${renderInlineTable s.help.run}
      desc = ${renderInlineTable s.help.description}
      hovered = ${renderInlineTable s.help.hovered}
      footer = ${renderInlineTable s.help.footer}

      [filetype]
      rules = [
        ${renderFileRule { url = "*/"; } f.directory},
        ${
          renderFileRule {
            url = "*";
            is = "exec";
          } f.executable
        },
        ${renderFileRule { mime = "application/zip"; } f.archive},
        ${renderFileRule { mime = "application/x-tar"; } f.archive},
        ${renderFileRule { mime = "application/x-gzip"; } f.archive},
        ${renderFileRule { mime = "application/x-bzip"; } f.archive},
        ${renderFileRule { mime = "application/x-7z-compressed"; } f.archive},
        ${renderFileRule { mime = "application/pdf"; } f.document},
        ${renderFileRule { mime = "application/msword"; } f.document},
        ${renderFileRule { mime = "application/vnd.*"; } f.document},
        ${renderFileRule { mime = "image/*"; } f.image},
        ${renderFileRule { mime = "video/*"; } f.media},
        ${renderFileRule { mime = "audio/*"; } f.media},
        ${renderFileRule { mime = "text/*"; } f.text},
        ${renderFileRule { url = "*.py"; } f.code},
        ${renderFileRule { url = "*.js"; } f.code},
        ${renderFileRule { url = "*.rs"; } f.code},
        ${renderFileRule { url = "*.go"; } f.code},
        ${renderFileRule { url = "*.c"; } f.code},
        ${renderFileRule { url = "*.cpp"; } f.code},
        ${renderFileRule { url = "*.h"; } f.code},
        ${renderFileRule { url = "*.java"; } f.code},
        ${renderFileRule { url = "*.toml"; } f.config},
        ${renderFileRule { url = "*.yaml"; } f.config},
        ${renderFileRule { url = "*.yml"; } f.config},
        ${renderFileRule { url = "*.json"; } f.config},
        ${renderFileRule { url = "*.xml"; } f.config},
        ${renderFileRule { url = "*.ini"; } f.config},
        ${renderFileRule { url = ".*"; } f.hidden},
        ${
          renderFileRule {
            url = "*";
            is = "link";
          } f.link
        },
        ${
          renderFileRule {
            url = "*";
            is = "orphan";
          } f.orphan
        },
        ${renderFileRule { mime = "inode/empty"; } f.empty},
        ${renderFileRule { url = "*"; } f.fallback},
      ]

      [icon]
      # Replace upstream's multicolor logo table with one inheriting marker per
      # file category. Directory lists are replaced because Yazi 26.5 colors
      # them explicitly and drops hex colors on merged directory conditions.
      dirs = []
      conds = [
        { if = "dir & hovered", text = "", fg = "${s.directoryIcon}" },
        { if = "dir", text = "", fg = "${s.directoryIcon}" },
      ]
      prepend_globs = [
        { url = "*.{jpg,jpeg,png,gif,bmp,webp,avif,tiff,tif,ico,svg,heic,heif}", text = "" },
        { url = "*.{mp4,mkv,webm,mov,avi,m4v,mpg,mpeg,wmv,flv}", text = "" },
        { url = "*.{mp3,flac,wav,ogg,opus,m4a,aac,wma,mid,midi}", text = "" },
        { url = "*.{zip,tar,gz,tgz,bz2,xz,zst,7z,rar,lz4,lzma,iso,dmg,deb,rpm}", text = "" },
        { url = "*.{pdf,epub,mobi,djvu,doc,docx,odt,rtf,ppt,pptx,xls,xlsx,ods,odp}", text = "" },
        { url = "*.{toml,yaml,yml,json,jsonc,ini,cfg,conf,env,lock,plist,xml}", text = "" },
        { url = "*.{md,markdown,txt,text,log,rst,org,adoc,tex,csv,tsv}", text = "" },
        { url = "*.{sh,bash,zsh,fish,ps1,bat,cmd}", text = "" },
        { url = "*.{nix,c,h,cc,cpp,hpp,rs,go,py,pyi,js,mjs,cjs,ts,tsx,jsx,lua,vim,rb,pl,php,java,kt,swift,scala,hs,ml,ex,exs,erl,clj,r,jl,zig,sql,css,scss,html,htm}", text = "" },
        { url = "**", text = "" },
      ]
    '';

  syntaxRules = [
    {
      name = "Comment";
      scope = "comment";
      style = "comment";
    }
    {
      name = "Constant, String, Number";
      scope = "constant, string, constant.numeric, constant.language, support.constant";
      style = "constant";
    }
    {
      name = "Keyword, Storage, Operator";
      scope = "keyword, storage, storage.modifier, keyword.operator, keyword.control";
      style = "keyword";
    }
    {
      name = "Type, Class, Storage Type";
      scope = "storage.type, support.type, entity.name.type, entity.name.class, entity.name.type.class";
      style = "type";
    }
    {
      name = "Function, Identifier";
      scope = "entity.name.function, variable, variable.parameter, support.function";
      style = "function";
    }
    {
      name = "Preprocessor";
      scope = "meta.preprocessor, keyword.control.import";
      style = "preprocessor";
    }
    {
      name = "Tag Name";
      scope = "entity.name.tag";
      style = "tag";
    }
    {
      name = "Tag Attribute";
      scope = "entity.other.attribute-name";
      style = "attribute";
    }
    {
      name = "Invalid";
      scope = "invalid";
      style = "invalid";
    }
    {
      name = "TODO";
      scope = "comment.line.todo, meta.toc-list.TODO";
      style = "todo";
    }
    {
      name = "Diff Added";
      scope = "markup.inserted";
      style = "diffAdded";
    }
    {
      name = "Diff Removed";
      scope = "markup.deleted";
      style = "diffRemoved";
    }
    {
      name = "Support Class";
      scope = "support.class";
      style = "supportClass";
    }
    {
      name = "Markup Heading";
      scope = "markup.heading, entity.name.section";
      style = "heading";
    }
    {
      name = "Markup Bold";
      scope = "markup.bold";
      style = "bold";
    }
    {
      name = "Markup Italic";
      scope = "markup.italic";
      style = "italic";
    }
    {
      name = "Markup Raw";
      scope = "markup.raw, markup.inline.raw, meta.code-fence";
      style = "raw";
    }
    {
      name = "Markup Link";
      scope = "markup.underline.link, meta.link, string.other.link";
      style = "link";
    }
    {
      name = "Markup List, Quote";
      # Do not include markup.list: syntect applies it to the whole list item.
      scope = "punctuation.definition.list_item, markup.quote";
      style = "list";
    }
    {
      name = "Markup Punctuation";
      scope = "punctuation.definition.heading, punctuation.definition.bold, punctuation.definition.italic, punctuation.definition.raw";
      style = "punctuation";
    }
  ];

  renderXmlSettings =
    settings:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: value: ''
        <key>${name}</key>
        <string>${value}</string>
      '') settings
    );

  renderSyntaxRule = styles: rule: ''
    <dict>
      <key>name</key>
      <string>${rule.name}</string>
      <key>scope</key>
      <string>${rule.scope}</string>
      <key>settings</key>
      <dict>
        ${renderXmlSettings styles.${rule.style}}
      </dict>
    </dict>
  '';

  mkTmTheme = theme: ''
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <!-- Generated by home/programs/yazi-theme.nix from the shared syntax
         schema and the ${theme.description}. -->
    <plist version="1.0">
    <dict>
      <key>name</key>
      <string>${theme.name}</string>
      <key>author</key>
      <string>${theme.author}</string>
      <key>settings</key>
      <array>
        <dict>
          <key>settings</key>
          <dict>
            ${renderXmlSettings theme.syntax.global}
          </dict>
        </dict>
        ${lib.concatMapStringsSep "\n" (renderSyntaxRule theme.syntax.styles) syntaxRules}
      </array>
      <key>uuid</key>
      <string>${theme.uuid}</string>
      <key>colorSpaceName</key>
      <string>sRGB</string>
      <key>semanticClass</key>
      <string>${theme.semanticClass}</string>
    </dict>
    </plist>
  '';
in
{
  xdg.configFile = {
    "yazi/flavors/${themes.dark.flavor}.yazi/flavor.toml".text = mkFlavor themes.dark;
    "yazi/flavors/${themes.dark.flavor}.yazi/tmtheme.xml".text = mkTmTheme themes.dark;
    "yazi/flavors/${themes.light.flavor}.yazi/flavor.toml".text = mkFlavor themes.light;
    "yazi/flavors/${themes.light.flavor}.yazi/tmtheme.xml".text = mkTmTheme themes.light;
  };
}
