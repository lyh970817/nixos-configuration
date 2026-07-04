{ config, pkgs, ... }:

let
  lightWallpaper = "$HOME/.local/share/wallpapers/Taiji_mandala.png";
  hyprCurrentTheme = "$HOME/.local/state/hypr/current-theme.conf";
  setClaudeTheme = theme: ''
    claude_settings="$HOME/.config/claude/settings.json"
    mkdir -p "$(dirname "$claude_settings")"
    if [ ! -e "$claude_settings" ]; then
      printf '{}\n' > "$claude_settings"
    fi
    claude_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$claude_settings.XXXXXX")"
    if ${pkgs.jq}/bin/jq --arg theme "${theme}" '.theme = $theme' "$claude_settings" > "$claude_settings_tmp"; then
      ${pkgs.coreutils}/bin/mv "$claude_settings_tmp" "$claude_settings"
    else
      ${pkgs.coreutils}/bin/rm -f "$claude_settings_tmp"
      echo "Failed to update Claude Code theme in $claude_settings" >&2
    fi
  '';

  # Dark Mode Script
  darkModeHook = pkgs.writeShellScript "dark-mode-hook" ''
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      mkdir -p "$HOME/.local/state/hypr"

      # 1. WALLPAPER (Kill old, start new)
        pkill swaybg || true
        ${pkgs.util-linux}/bin/setsid -f ${pkgs.swaybg}/bin/swaybg -c 000000 >/dev/null 2>&1

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

    ln -sf $HOME/.config/fzf/themes/dark $HOME/.config/fzf/current_theme

    ln -sf $HOME/.config/newt/themes/dark $HOME/.config/newt/current_theme


      # 1. GTK THEME (Crucial for Hyprland)
      # Sets the "System" preference to dark
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
      # (Optional) Force a specific dark GTK theme if you have one installed, e.g., Adwaita-dark
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'Trinity'
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'Matrix-Icons'
      ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme 'Hacker-C'

      # Alacritty: Update symlink (alacritty auto-reloads on import changes)
      ln -sf $HOME/.config/alacritty/themes/dark.toml $HOME/.config/alacritty/current.toml

      ${setClaudeTheme "dark-ansi"}

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

    ln -sf $HOME/.config/fzf/themes/light $HOME/.config/fzf/current_theme

    ln -sf $HOME/.config/newt/themes/light $HOME/.config/newt/current_theme

    # 1. GTK THEME
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    # (Optional) Force a specific light GTK theme
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'HighContrast'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'HighContrast'
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'

    echo "--color=info:#404040,prompt:#404040,pointer:#000000,marker:#000000" > $HOME/.config/fzf-theme

    # Alacritty: Update symlink (alacritty auto-reloads on import changes)
    ln -sf $HOME/.config/alacritty/themes/light.toml $HOME/.config/alacritty/current.toml

    ${setClaudeTheme "light-ansi"}

    # Mako: Remove dark mode
    ${pkgs.mako}/bin/makoctl mode -r dark
    ${pkgs.mako}/bin/makoctl reload

    hyprctl setcursor Adwaita 24
  '';
in
{
  # Theme switching scripts
  home.packages = with pkgs; [
    (pkgs.writeShellScriptBin "switch-dark" "${darkModeHook}")
    (pkgs.writeShellScriptBin "switch-light" "${lightModeHook}")
  ];

  # Darkman service
  systemd.user.services.darkman = {
    Unit = {
      Description = "Darkman Service";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.darkman}/bin/darkman run";
      Restart = "always";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Darkman hook symlinks
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
