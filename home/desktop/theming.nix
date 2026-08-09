{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;

  lightWallpaper = "$HOME/.local/share/wallpapers/Taiji_mandala.png";
  hyprCurrentTheme = "$HOME/.local/state/hypr/current-theme.conf";

  # Dark-mode cursor. Bibata Original rebuilt in a utilitarian grey with a
  # near-black outline and phosphor green only in the loading spinner, so the
  # pointer reads as an ordinary pointer on a modern laptop rather than as part
  # of the terminal. See pkgs/bibata-vt220-cursors.nix; it is installed through
  # home/packages/desktop.nix, because a cursor-theme name that is not on the
  # icon search path resolves to nothing and falls back silently.
  #
  # The name is taken from the package rather than spelled again, so renaming
  # the theme cannot leave a dangling reference here.
  #
  # Light mode is out of scope and stays on Adwaita at 24; it only gains an
  # explicit cursor-size write below, because gsettings is global state and
  # would otherwise inherit dark mode's 22 the next time the mode flips.
  darkCursorTheme = pkgs.bibata-vt220-cursors.themeName;
  darkCursorSize = 22;
  lightCursorTheme = "Adwaita";
  lightCursorSize = 24;

  # VT220-Amber is generated, not stored. assets/themes/VT220-Amber is a
  # template tree whose phosphor colours are rung tokens spelled @name@; this
  # substitutes the active profile into a copy of it. Storing hex instead is
  # what let the theme fall a whole palette retune behind the rungs it was
  # generated from -- see 015165f9, which corrected one property and left 128
  # stale hexes in gtk.css. Semantic non-phosphor colours (error red, warning
  # orange, info blue, the neutral question grey) stay literal in the template.
  #
  # All ten rungs are offered even though the theme names only six, so a
  # template edit can reach any of them without touching this list.
  themeTokens = pkgs.lib.mapAttrs (_: v: "#${v}") p;

  # PNG assets are the only binaries in the tree; every other file is text that
  # may name a token. Nothing in the template legitimately contains a bare
  # @word@, so any survivor is a misspelled rung -- fail the build rather than
  # ship a theme with "@forground@" in it.
  vt220Theme = pkgs.runCommand "vt220-amber-theme" { } ''
    cp -r ${../../assets/themes/VT220-Amber} $out
    chmod -R u+w $out
    find $out -type f ! -name '*.png' -print0 | xargs -0 sed -i \
      ${pkgs.lib.concatStringsSep " \\\n      " (
        pkgs.lib.mapAttrsToList (n: v: "-e 's/@${n}@/${v}/g'") themeTokens
      )}
    if grep -rIn '@[A-Za-z][A-Za-z0-9]*@' $out; then
      echo "vt220-amber-theme: unsubstituted token above; check the rung name" >&2
      echo "against home/palettes.nix" >&2
      exit 1
    fi
  '';

  # Dark Mode Script
  #
  # This hook only drives Layer A (this machine's own desktop appearance:
  # wallpaper, Hyprland, GTK, rofi, alacritty, mako, cursor). fzf, newt, btop,
  # nvim, and Claude Code no longer follow it — they now read the per-session
  # THEME_MODE variable set by theme-hold instead (see below).
  darkModeHook = pkgs.writeShellScript "dark-mode-hook" ''
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$HOME/.local/state/hypr"

    # 1. WALLPAPER (Kill old, start new)
    pkill swaybg || true
    ${pkgs.util-linux}/bin/setsid -f ${pkgs.swaybg}/bin/swaybg -c ${p.background} >/dev/null 2>&1
    ${pkgs.systemd}/bin/systemctl --user start mandala-wallpaper.service || true

    # 2. HYPRLAND BACKGROUND COLOR (Misc setting)
    ${pkgs.hyprland}/bin/hyprctl keyword misc:background_color 0x${p.background}
    # Panel shader. Its predecessor was disabled because a warm-tinted bloom
    # and black lift cast amber over the green phosphor and contaminated any
    # colour measured from a screenshot; the lift is gone and the surviving
    # tints follow the phosphor, so that objection no longer applies. Light
    # mode still leaves it empty.
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:screen_shader "$HOME/.config/hypr/shaders/panel.glsl"

    # 3. HYPRLAND THEME (Symlink + Live Settings)
    ln -sf "$HOME/.config/hypr/themes/dark.conf" "${hyprCurrentTheme}"

    # Live update gaps/borders
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 8
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 12
    ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 1
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(${p.accent}ff)"
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.inactive_border "rgba(${p.subtleBorder}ff)"
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:rounding 4
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:active_opacity 1
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:inactive_opacity 1

    ln -sf $HOME/.config/rofi/themes/dark.rasi $HOME/.config/rofi/current.rasi

    # 1. GTK THEME (Crucial for Hyprland)
    # Sets the "System" preference to dark
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    # (Optional) Force a specific dark GTK theme if you have one installed, e.g., Adwaita-dark
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'VT220-Amber'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'Matrix-Icons'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme '${darkCursorTheme}'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-size ${toString darkCursorSize}

    # Terminals: select the palette used by new windows.
    ln -sf $HOME/.config/alacritty/themes/dark.toml $HOME/.config/alacritty/current.toml
    ln -sf $HOME/.config/foot/themes/dark.ini $HOME/.config/foot/foot.ini

    # Claude Code: rewrite the theme in each profile's settings.json.
    ${claudeTheme}/bin/claude-theme dark

    # Mako: Switch mode
    ${pkgs.mako}/bin/makoctl mode -a dark
    ${pkgs.mako}/bin/makoctl reload

    # Cursor. Two independent consumers, and setting only the first is what
    # makes a mode switch look half-applied:
    #   - the compositor's own pointer (desktop, gaps, borders), from setcursor;
    #   - clients that load an XCursor theme themselves -- foot,
    #     Chromium/Electron, anything on libwayland-cursor -- which read
    #     XCURSOR_THEME/XCURSOR_SIZE once, from the environment they started in.
    # `hyprctl keyword env` rewrites Hyprland's own environment, so every client
    # spawned after the switch agrees with the compositor. Clients that were
    # already running keep the cursor they started with until they restart;
    # nothing can reach into their environment after the fact.
    ${pkgs.hyprland}/bin/hyprctl setcursor ${darkCursorTheme} ${toString darkCursorSize}
    ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_THEME,${darkCursorTheme}
    ${pkgs.hyprland}/bin/hyprctl keyword env HYPRCURSOR_THEME,${darkCursorTheme}
    ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_SIZE,${toString darkCursorSize}

  '';

  # Light Mode Script
  lightModeHook = pkgs.writeShellScript "light-mode-hook" ''
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$HOME/.local/state/hypr"

    ln -sf "$HOME/.config/hypr/themes/light.conf" "${hyprCurrentTheme}"

    # WALLPAPER
    ${pkgs.systemd}/bin/systemctl --user stop mandala-wallpaper.service || true
    pkill swaybg || true
    ${pkgs.util-linux}/bin/setsid -f ${pkgs.swaybg}/bin/swaybg -i "${lightWallpaper}" -m fit -c ffffff >/dev/null 2>&1

    # 2. HYPRLAND BACKGROUND COLOR
    ${pkgs.hyprland}/bin/hyprctl keyword misc:background_color 0xffffff
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:screen_shader '[[EMPTY]]'

    # Live update gaps/borders
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 4
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 15
    ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 2
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(000000ff)"
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.inactive_border "rgba(00000000)"
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:rounding 4
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:active_opacity 1
    ${pkgs.hyprland}/bin/hyprctl keyword decoration:inactive_opacity 0.7

    ln -sf $HOME/.config/rofi/themes/light.rasi $HOME/.config/rofi/current.rasi

    # 1. GTK THEME
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    # (Optional) Force a specific light GTK theme
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'HighContrast'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'HighContrast'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme '${lightCursorTheme}'
    # Pins what light mode already gets from the schema default. Only dark mode
    # changed size, but cursor-size is one global key, so without this write
    # light mode would keep dark mode's 22 and disagree with its own setcursor.
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-size ${toString lightCursorSize}

    # Terminals: select the palette used by new windows.
    ln -sf $HOME/.config/alacritty/themes/light.toml $HOME/.config/alacritty/current.toml
    ln -sf $HOME/.config/foot/themes/light.ini $HOME/.config/foot/foot.ini

    # Claude Code: rewrite the theme in each profile's settings.json.
    ${claudeTheme}/bin/claude-theme light

    # Mako: Remove dark mode
    ${pkgs.mako}/bin/makoctl mode -r dark
    ${pkgs.mako}/bin/makoctl reload

    # See the dark hook for why the environment is rewritten alongside setcursor.
    ${pkgs.hyprland}/bin/hyprctl setcursor ${lightCursorTheme} ${toString lightCursorSize}
    ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_THEME,${lightCursorTheme}
    ${pkgs.hyprland}/bin/hyprctl keyword env HYPRCURSOR_THEME,${lightCursorTheme}
    ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_SIZE,${toString lightCursorSize}
  '';

  # Peer machine to notify on theme edges, baked from the host config. Empty
  # string ("" default) disables cross-machine sync entirely.
  peerHost = osConfig.portable.peerHost;

  # theme-push: fire-and-forget notification of a mode change to the peer over
  # Tailscale SSH (keyless). Fully detached and silent so it never blocks the
  # caller and never prints. No-op when no peer is configured. It runs
  # switch-<mode> on the peer, and switch-* never pushes, so this cannot loop.
  #
  # Each machine now follows its own monitor (Layer A), so automatic
  # cross-machine sync on a monitor edge would fight that rule instead of
  # helping it — monitor-switch.sh no longer calls this. The only surviving
  # caller is theme-toggle: a deliberate, manual global preference ("make
  # everything dark tonight"), not automatic sync.
  themePush = pkgs.writeShellScriptBin "theme-push" ''
    PEER="${peerHost}"
    [ -n "$PEER" ] || exit 0
    case "$1" in
    light | dark) ;;
    *) exit 0 ;;
    esac
    timeout 3 ssh -o ConnectTimeout=2 "$PEER" "switch-$1" >/dev/null 2>&1 &
  '';

  # theme-toggle: flip the currently applied mode, apply it locally, then push
  # to the peer. Bound to a key by another workstream. The current mode is
  # derived from the hypr current-theme symlink target, defaulting to dark when
  # unknown. The receiving peer runs switch-* (which never pushes), so this
  # cannot loop.
  themeToggle = pkgs.writeShellScriptBin "theme-toggle" ''
    target="$(readlink "${hyprCurrentTheme}" 2>/dev/null || true)"
    case "$target" in
    *light.conf) new="dark" ;;
    *dark.conf) new="light" ;;
    *) new="light" ;;
    esac
    switch-"$new"
    theme-push "$new"
  '';

  # theme-mode: prints the currently applied mode, derived from the hypr
  # current-theme symlink target using the same idiom (and the same "light"
  # default when unknown) as theme-toggle above. Used by the ssh/mosh client
  # wrappers and home-terminal to learn which mode to hand off to the peer.
  themeMode = pkgs.writeShellScriptBin "theme-mode" ''
    target="$(readlink "${hyprCurrentTheme}" 2>/dev/null || true)"
    case "$target" in
    *light.conf) echo light ;;
    *dark.conf) echo dark ;;
    *) echo light ;;
    esac
  '';

  # claude-theme: usage `claude-theme <dark|light>`. Writes the matching theme
  # into every Claude Code profile's settings.json.
  #
  # This keeps the *fallback* theme in step with the mode. Sessions started
  # through the launcher in programs/claude.nix are already themed from
  # THEME_MODE via --settings, which outranks settings.json; the ones that skip
  # it -- Claude Code's agent view and background daemon re-exec the binary
  # directly -- read settings.json instead, so that copy has to track the mode
  # rather than sit on one value.
  #
  # `dark-ansi` and `light-ansi` are the only two themes that draw purely
  # through ANSI slots, and so the only ones that follow the phosphor ladder in
  # dark mode and the e-ink black-on-white in light. `auto` ("match terminal")
  # sounds like the answer and is not: it only chooses between the two 24-bit
  # themes, both of which ignore the terminal palette.
  #
  # Dark mode names the custom theme installed by programs/mutable-configs.nix,
  # which is dark-ansi with three slab backgrounds moved off ANSI bright black
  # so that slot can carry a readable rung. A slug that fails to resolve falls
  # back to the 24-bit "dark" theme silently, so this string has to match the
  # theme file name there.
  #
  # Only newly started sessions pick this up, the same as alacritty windows.
  # Activation writes the same key from the same source (the reconciler in
  # programs/mutable-configs.nix), so the two writers cannot disagree.
  claudeTheme = pkgs.writeShellScriptBin "claude-theme" ''
    case "$1" in
    dark) theme="custom:phosphor-dark" ;;
    light) theme="light-ansi" ;;
    *) exit 0 ;;
    esac

    for dir in claude claude-mattpocock claude-gpt56; do
      settings="$HOME/.config/$dir/settings.json"
      [ -f "$settings" ] || continue
      tmp="$(${pkgs.coreutils}/bin/mktemp "$settings.XXXXXX")" || continue
      if ${pkgs.jq}/bin/jq --arg theme "$theme" '.theme = $theme' "$settings" >"$tmp"; then
        ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
        ${pkgs.coreutils}/bin/mv -f "$tmp" "$settings"
      else
        ${pkgs.coreutils}/bin/rm -f "$tmp"
      fi
    done
  '';

  # theme-hold: usage `theme-hold <mode> <command...>`. Exports THEME_MODE
  # into the wrapped process and execs it in place. exec preserves the PID,
  # and the export survives into the wrapped session process (tmux client or
  # login shell) and everything it forks, so the mode is set once at launch
  # and frozen for that process's life. This is the entire transport for
  # session colours; it never touches this machine's own desktop appearance.
  themeHold = pkgs.writeShellScriptBin "theme-hold" ''
    case "$1" in
    dark | light) export THEME_MODE="$1" ;;
    esac
    shift
    exec "$@"
  '';
in
{
  # Theme switching scripts
  home.packages = with pkgs; [
    (pkgs.writeShellScriptBin "switch-dark" "${darkModeHook}")
    (pkgs.writeShellScriptBin "switch-light" "${lightModeHook}")
    claudeTheme
    themePush
    themeToggle
    themeMode
    themeHold
  ];

  # Monitor presence in hypr/scripts/monitor-switch.sh is the sole automatic
  # theme trigger; it calls switch-light/switch-dark directly. The Darkman
  # daemon is intentionally not started because this configuration manages no
  # Darkman schedule, location, or other Darkman configuration.

  # Legacy Darkman hook locations expose the same theme actions, but the
  # monitor-switch script is what selects and invokes a mode automatically.
  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/hypr 0755 - - -"
    "L %h/.local/state/hypr/current-theme.conf - - - - %h/.config/hypr/themes/dark.conf"
    "L+ %h/.local/share/dark-mode.d/10-nixos-hook.sh - - - - ${darkModeHook}"
    "L+ %h/.local/share/light-mode.d/10-nixos-hook.sh - - - - ${lightModeHook}"
  ];

  # Managed theme assets. Dark mode pairs VT220-Amber with the Matrix-Icons
  # set (packaged in pkgs/matrix-icons.nix, installed via home/packages);
  # that set is green throughout, so it matches the phosphor palette instead
  # of the white raster icons HighContrast was falling back to. The cursor is
  # Bibata-Original-VT220 (see darkCursorTheme above); light mode keeps Adwaita.
  xdg.dataFile."wallpapers/Taiji_mandala.png".source = ../../assets/wallpapers/Taiji_mandala.png;
  xdg.dataFile."themes/VT220-Amber".source = vt220Theme;
}
