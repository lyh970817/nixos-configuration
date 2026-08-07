{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  lightWallpaper = "$HOME/.local/share/wallpapers/Taiji_mandala.png";
  hyprCurrentTheme = "$HOME/.local/state/hypr/current-theme.conf";

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
    ${pkgs.util-linux}/bin/setsid -f ${pkgs.swaybg}/bin/swaybg -c 000000 >/dev/null 2>&1
    ${pkgs.systemd}/bin/systemctl --user start mandala-wallpaper.service || true

    # 2. HYPRLAND BACKGROUND COLOR (Misc setting)
    ${pkgs.hyprland}/bin/hyprctl keyword misc:background_color 0x000000

    # 3. HYPRLAND THEME (Symlink + Live Settings)
    ln -sf "$HOME/.config/hypr/themes/dark.conf" "${hyprCurrentTheme}"

    # Live update gaps/borders
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 20
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 30
    ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 2
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(056608ff)"

    ln -sf $HOME/.config/rofi/themes/dark.rasi $HOME/.config/rofi/current.rasi

    # 1. GTK THEME (Crucial for Hyprland)
    # Sets the "System" preference to dark
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    # (Optional) Force a specific dark GTK theme if you have one installed, e.g., Adwaita-dark
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'Trinity'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'Matrix-Icons'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme 'Hacker-C'

    # Terminals: select the palette used by new windows.
    ln -sf $HOME/.config/alacritty/themes/dark.toml $HOME/.config/alacritty/current.toml
    ln -sf $HOME/.config/foot/themes/dark.ini $HOME/.config/foot/foot.ini

    # Mako: Switch mode
    ${pkgs.mako}/bin/makoctl mode -a dark
    ${pkgs.mako}/bin/makoctl reload

    hyprctl setcursor Hacker-C 24

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

    # Live update gaps/borders
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 4
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 15
    ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 2
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(000000ff)"

    ln -sf $HOME/.config/rofi/themes/light.rasi $HOME/.config/rofi/current.rasi

    # 1. GTK THEME
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    # (Optional) Force a specific light GTK theme
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'HighContrast'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'HighContrast'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'

    # Terminals: select the palette used by new windows.
    ln -sf $HOME/.config/alacritty/themes/light.toml $HOME/.config/alacritty/current.toml
    ln -sf $HOME/.config/foot/themes/light.ini $HOME/.config/foot/foot.ini

    # Mako: Remove dark mode
    ${pkgs.mako}/bin/makoctl mode -r dark
    ${pkgs.mako}/bin/makoctl reload

    hyprctl setcursor Adwaita 24
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

  # Managed Assets (Themes & Icons)
  xdg.dataFile."wallpapers/Taiji_mandala.png".source = ../../assets/wallpapers/Taiji_mandala.png;
  xdg.dataFile."themes/Trinity".source = ../../assets/themes/Trinity;
  xdg.dataFile."icons/Matrix-Icons".source = ../../assets/icons/Matrix-Icons;
  xdg.dataFile."icons/Hacker-C".source = ../../assets/icons/Hacker-C;
}
