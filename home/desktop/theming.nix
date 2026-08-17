{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;

  lightWallpaper = "$HOME/.local/share/wallpapers/Taiji_mandala.png";

  # Dark wallpaper: a rock-art frieze tinted to the phosphor ladder. Stored
  # rendered rather than generated from a rung, because its green (#76D87D)
  # is deliberately between `bright` and `hot` in ../palettes.nix and is not a
  # named rung -- see the recipe in the asset comment below. Centred at its
  # native 1254x706 rather than `fit`, so the figures keep the 1:1 pixel scale
  # they were tuned at and the surrounding field stays flat background.
  darkWallpaper = "$HOME/.local/share/wallpapers/Petroglyph_frieze.png";
  # Hyprland's config is Lua (the .conf format is removed in 0.57), so the mode
  # marker is a .lua symlink and every reader below matches *dark.lua /
  # *light.lua. See dotfiles/hypr/hyprland.lua.
  hyprCurrentTheme = "$HOME/.local/state/hypr/current-theme.lua";

  # TRANSITIONAL twin of the marker above. hyprland.conf sources this path, so
  # a compositor that started before the migration reads its mode from here
  # while everything else reads the .lua marker. Every writer below sets both,
  # so a dark/light switch made under a hyprlang session is still correct after
  # the user relogs into Lua, and vice versa. Delete with the rest of the
  # legacy set; see the header of ../../dotfiles/hypr/hyprland.conf.
  hyprCurrentThemeLegacy = "$HOME/.local/state/hypr/current-theme.conf";

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
  # wallpaper, Hyprland, GTK, rofi, foot, mako, cursor). fzf, newt, btop,
  # nvim, and Claude Code no longer follow it — they now read the per-session
  # THEME_MODE variable set by theme-hold instead (see below).
  darkModeHook = pkgs.writeShellScript "dark-mode-hook" ''
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$HOME/.local/state/hypr"

    # Make the mode authoritative before reconciling the output-aware shader.
    ln -sf "$HOME/.config/hypr/themes/dark.lua" "${hyprCurrentTheme}"
    ln -sf "$HOME/.config/hypr/themes/dark.conf" "${hyprCurrentThemeLegacy}"
    ${pkgs.screen-shader-controller}/bin/screen-shader reconcile --mode dark

    # 1. WALLPAPER (Kill old, start new)
    pkill swaybg || true
    ${pkgs.util-linux}/bin/setsid -f ${pkgs.swaybg}/bin/swaybg -i "${darkWallpaper}" -m center -c ${p.background} >/dev/null 2>&1
    ${pkgs.systemd}/bin/systemctl --user start mandala-wallpaper.service || true

    # 2/3. HYPRLAND BACKGROUND COLOR + LIVE THEME SETTINGS
    #
    # The Lua manager reloads the complete mode fragment; the legacy manager
    # still needs individual keyword writes. TRANSITIONAL -- delete the legacy
    # arm with pkgs/hypr-ipc.nix.
    if [ "$(${pkgs.hypr-ipc}/bin/hypr-ipc manager)" = legacy ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword misc:background_color 0x${p.background}
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 8
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 12
      ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 1
      ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(3D8E48ff)"
      ${pkgs.hyprland}/bin/hyprctl keyword general:col.inactive_border "rgba(15261Aff)"
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:rounding 4
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:active_opacity 1
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:inactive_opacity 1
      # The legacy manager cannot express reload-safe rule handles, so retain
      # the ordinary dark window treatment instead of leaking the app shadow
      # to every window.
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:shadow:enabled false
    else
      # The marker now points at the complete mode-specific Lua config. Reload
      # once so its settings and named-rule state change together; Hyprland's
      # startup handlers do not rerun on config reload.
      ${pkgs.hyprland}/bin/hyprctl reload
    fi

    ln -sf $HOME/.config/rofi/themes/dark.rasi $HOME/.config/rofi/current.rasi

    # 1. GTK THEME (Crucial for Hyprland)
    # Sets the "System" preference to dark
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    # (Optional) Force a specific dark GTK theme if you have one installed, e.g., Adwaita-dark
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'VT220-Amber'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'Matrix-Icons'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme '${darkCursorTheme}'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-size ${toString darkCursorSize}

    # Terminal: select the palette used by new windows.
    ln -sf $HOME/.config/foot/themes/dark.ini $HOME/.config/foot/foot.ini
    # The managed btop dashboard is a persistent Foot process, and btop leaves
    # that terminal background visible. Restart that dashboard on the mode
    # switch so the managed Foot window picks up the new palette; session-scoped
    # btop instances already inherit the right colors when they launch.
    ${pkgs.systemd}/bin/systemctl --user try-restart btop-dashboard.service || true

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
    # `hl.env` rewrites Hyprland's own environment, so every client spawned
    # after the switch agrees with the compositor. Clients that were already
    # running keep the cursor they started with until they restart; nothing can
    # reach into their environment after the fact.
    ${pkgs.hyprland}/bin/hyprctl setcursor ${darkCursorTheme} ${toString darkCursorSize}
    if [ "$(${pkgs.hypr-ipc}/bin/hypr-ipc manager)" = legacy ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_THEME,${darkCursorTheme}
      ${pkgs.hyprland}/bin/hyprctl keyword env HYPRCURSOR_THEME,${darkCursorTheme}
      ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_SIZE,${toString darkCursorSize}
    else
      ${pkgs.hyprland}/bin/hyprctl eval '
        hl.env("XCURSOR_THEME", "${darkCursorTheme}")
        hl.env("HYPRCURSOR_THEME", "${darkCursorTheme}")
        hl.env("XCURSOR_SIZE", "${toString darkCursorSize}")
      '
    fi

  '';

  # Light Mode Script
  lightModeHook = pkgs.writeShellScript "light-mode-hook" ''
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    mkdir -p "$HOME/.local/state/hypr"

    # Make the mode authoritative before reconciling the output-aware shader.
    ln -sf "$HOME/.config/hypr/themes/light.lua" "${hyprCurrentTheme}"
    ln -sf "$HOME/.config/hypr/themes/light.conf" "${hyprCurrentThemeLegacy}"
    ${pkgs.screen-shader-controller}/bin/screen-shader reconcile --mode light

    # WALLPAPER
    ${pkgs.systemd}/bin/systemctl --user stop mandala-wallpaper.service || true
    pkill swaybg || true
    ${pkgs.util-linux}/bin/setsid -f ${pkgs.swaybg}/bin/swaybg -i "${lightWallpaper}" -m fit -c ffffff >/dev/null 2>&1

    # 2. HYPRLAND BACKGROUND COLOR + live theme settings. See the dark hook for
    # why the legacy arm exists.
    if [ "$(${pkgs.hypr-ipc}/bin/hypr-ipc manager)" = legacy ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword misc:background_color 0xffffff
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 4
      ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 15
      ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 2
      ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(000000ff)"
      ${pkgs.hyprland}/bin/hyprctl keyword general:col.inactive_border "rgba(00000000)"
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:rounding 4
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:active_opacity 1
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:inactive_opacity 0.7
      ${pkgs.hyprland}/bin/hyprctl keyword decoration:shadow:enabled false
    else
      # See the dark hook: the light theme owns the same complete setting set,
      # so one reload applies it without an intermediate visual state.
      ${pkgs.hyprland}/bin/hyprctl reload
    fi

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

    # Terminal: select the palette used by new windows.
    ln -sf $HOME/.config/foot/themes/light.ini $HOME/.config/foot/foot.ini
    # See the dark hook: session-scoped btop launches with the right config,
    # but the managed dashboard still needs its persistent Foot window
    # recreated to pick up the new background.
    ${pkgs.systemd}/bin/systemctl --user try-restart btop-dashboard.service || true

    # Claude Code: rewrite the theme in each profile's settings.json.
    ${claudeTheme}/bin/claude-theme light

    # Mako: Remove dark mode
    ${pkgs.mako}/bin/makoctl mode -r dark
    ${pkgs.mako}/bin/makoctl reload

    # See the dark hook for why the environment is rewritten alongside setcursor.
    ${pkgs.hyprland}/bin/hyprctl setcursor ${lightCursorTheme} ${toString lightCursorSize}
    if [ "$(${pkgs.hypr-ipc}/bin/hypr-ipc manager)" = legacy ]; then
      ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_THEME,${lightCursorTheme}
      ${pkgs.hyprland}/bin/hyprctl keyword env HYPRCURSOR_THEME,${lightCursorTheme}
      ${pkgs.hyprland}/bin/hyprctl keyword env XCURSOR_SIZE,${toString lightCursorSize}
    else
      ${pkgs.hyprland}/bin/hyprctl eval '
        hl.env("XCURSOR_THEME", "${lightCursorTheme}")
        hl.env("HYPRCURSOR_THEME", "${lightCursorTheme}")
        hl.env("XCURSOR_SIZE", "${toString lightCursorSize}")
      '
    fi
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
    *light.lua) new="dark" ;;
    *dark.lua) new="light" ;;
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
    *light.lua) echo light ;;
    *dark.lua) echo dark ;;
    *) echo light ;;
    esac
  '';

  # claude-theme: usage `claude-theme <dark|light>`. Writes the matching theme
  # into every Claude Code profile's settings.json.
  #
  # This keeps the *machine-mode fallback* theme in step with the mode. Sessions
  # started through the launcher in programs/claude.nix, including Claude's
  # own re-execs through CLAUDE_CODE_PROCESS_WRAPPER, are already themed from
  # their inherited THEME_MODE via --settings, which outranks settings.json.
  # Only a truly direct, unwrapped binary launch needs the on-disk copy.
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
  # Only newly started sessions pick this up, the same as foot windows.
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
    screen-shader-controller
  ];

  # A separate watcher, rather than the exec-once monitor/theme loop, adopts a
  # new controller immediately after Home Manager switches generations.
  systemd.user.services.screen-shader-watch = {
    Unit = {
      Description = "Keep the laptop-panel shader reconciled with Hyprland outputs";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.screen-shader-controller}/bin/screen-shader watch";
      Restart = "on-failure";
      RestartSec = "2s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # graphical-session.target is already active during a rebuild, so adding a
  # WantedBy edge alone would not start a newly introduced watcher. Restart it
  # after the units are reloaded so policy changes take effect in this session.
  home.activation.restartScreenShaderWatch = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    if ${pkgs.systemd}/bin/systemctl --user is-active --quiet graphical-session.target; then
      run ${pkgs.systemd}/bin/systemctl --user restart screen-shader-watch.service
    fi
  '';

  # Monitor presence in hypr/scripts/monitor-switch.sh is the sole automatic
  # theme trigger; it calls switch-light/switch-dark directly. Keep the common
  # freedesktop hook locations as compatibility entry points for those actions.
  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/hypr 0755 - - -"
    "L %h/.local/state/hypr/current-theme.lua - - - - %h/.config/hypr/themes/dark.lua"
    # TRANSITIONAL twin; see hyprCurrentThemeLegacy above.
    "L %h/.local/state/hypr/current-theme.conf - - - - %h/.config/hypr/themes/dark.conf"
    "L+ %h/.local/share/dark-mode.d/10-nixos-hook.sh - - - - ${darkModeHook}"
    "L+ %h/.local/share/light-mode.d/10-nixos-hook.sh - - - - ${lightModeHook}"
  ];

  # TRANSITIONAL: keep the two mode markers in step, in whichever direction
  # they disagree, on every activation.
  #
  # Both directions are needed and both were live during this migration. A
  # machine coming from the .conf era has only the legacy marker, and it may
  # say light -- the tmpfiles `L` rules above only fill a *missing* path and
  # both name dark, so without this the .lua marker is born saying "dark" and
  # flips the desktop at the next rebuild. Going the other way, a machine that
  # has already relogged into Lua switches modes through the .lua marker only
  # while its .conf marker sits at whatever it last was; if that machine is
  # ever rolled back (which is exactly what happened here), the stale legacy
  # marker would put the desktop in the wrong mode.
  #
  # The .lua marker is the source of truth wherever both exist -- it is the one
  # theme-mode, theme-toggle and screen-shader read. Runs on every activation
  # rather than once, so neither marker can be left behind by a rollback, and
  # is self-sufficient rather than ordered against tmpfiles.
  home.activation.hyprThemeMarkerSync = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    themes="$HOME/.config/hypr/themes"
    lua="${hyprCurrentTheme}"
    conf="${hyprCurrentThemeLegacy}"

    run mkdir -p "$HOME/.local/state/hypr"

    if [ -L "$lua" ] || [ -e "$lua" ]; then
      # .lua wins: mirror it into the legacy marker.
      case "$(readlink "$lua" 2>/dev/null || true)" in
      *light.lua) mode=light ;;
      *) mode=dark ;;
      esac
    elif [ -L "$conf" ] || [ -e "$conf" ]; then
      # First activation after the migration on a machine that only has the
      # legacy marker: adopt whatever mode it is actually in.
      case "$(readlink "$conf" 2>/dev/null || true)" in
      *light.conf) mode=light ;;
      *) mode=dark ;;
      esac
    else
      mode=dark
    fi

    [ "$(readlink "$lua" 2>/dev/null || true)" = "$themes/$mode.lua" ] \
      || run ln -sfn "$themes/$mode.lua" "$lua"
    [ "$(readlink "$conf" 2>/dev/null || true)" = "$themes/$mode.conf" ] \
      || run ln -sfn "$themes/$mode.conf" "$conf"
  '';

  # Foot reads its palette from ~/.config/foot/foot.ini once, when the window
  # opens, so that symlink has to exist before the first mode switch of a
  # session -- and it has to agree with the mode already applied. It used to be
  # seeded by a tmpfiles `L` rule in ../programs/foot.nix, which can only name
  # one fixed target and named the dark theme: when the foot module first
  # landed on a desktop that had been in light mode since the previous
  # generation, `L` filled the missing path with the dark phosphor palette and
  # every foot window came up dark until the next manual switch. The hooks
  # above only run on a mode *change*, so nothing corrected it.
  #
  # Reconcile it here instead, from the same current-theme symlink theme-mode
  # reads, and on every activation rather than only when missing, so a rebuild
  # cannot leave the terminal disagreeing with the desktop. Dark mode keeps
  # whichever dark-*.ini is linked so an active `phosphor` selection survives.
  home.activation.footThemeLink = lib.hm.dag.entryAfter [ "hyprThemeMarkerSync" ] ''
    themes="$HOME/.config/foot/themes"
    link="$HOME/.config/foot/foot.ini"
    current="$(readlink "$link" 2>/dev/null || true)"

    case "$(readlink "${hyprCurrentTheme}" 2>/dev/null || true)" in
    *light.lua) want="$themes/light.ini" ;;
    *)
      case "$current" in
      "$themes"/dark-*.ini) want="$current" ;;
      *) want="$themes/dark.ini" ;;
      esac
      ;;
    esac

    [ "$current" = "$want" ] || run ln -sfn "$want" "$link"
  '';

  # Managed theme assets. Dark mode pairs VT220-Amber with the Matrix-Icons
  # set (packaged in pkgs/matrix-icons.nix, installed via home/packages);
  # that set is green throughout, so it matches the phosphor palette instead
  # of the white raster icons HighContrast was falling back to. The cursor is
  # Bibata-Original-VT220 (see darkCursorTheme above); light mode keeps Adwaita.
  xdg.dataFile."wallpapers/Taiji_mandala.png".source = ../../assets/wallpapers/Taiji_mandala.png;

  # Rendered from an untinted rock-art scan by mapping its greyscale through a
  # background -> green gradient, so the figures glow on the same brown-black
  # the compositor paints. To retune the green, rerun with a different endpoint:
  #
  #   magick <original>.png -resize 75% -colorspace gray -auto-level \
  #     -level '7%,100%' \( -size 256x1 'gradient:#050806-#76D87D' \) -clut \
  #     assets/wallpapers/Petroglyph_frieze.png
  xdg.dataFile."wallpapers/Petroglyph_frieze.png".source =
    ../../assets/wallpapers/Petroglyph_frieze.png;
  xdg.dataFile."themes/VT220-Amber".source = vt220Theme;
}
