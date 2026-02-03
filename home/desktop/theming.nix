{ config, pkgs, ... }:

let
  # Dark Mode Script
  darkModeHook = pkgs.writeShellScript "dark-mode-hook" ''
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"

  # 1. WALLPAPER (Kill old, start new)
    pkill swaybg
    ${pkgs.swaybg}/bin/swaybg -c 000000 &

    # 2. HYPRLAND BACKGROUND COLOR (Misc setting)
    ${pkgs.hyprland}/bin/hyprctl keyword misc:background_color 0x000000

    # 3. HYPRLAND THEME (Symlink + Live Settings)
    ln -sf /home/andongni/.config/hypr/themes/dark.conf /home/andongni/.config/hypr/themes/current.conf

    # Live update gaps/borders
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 20
    ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 30
    ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 2
    ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(056608ff)"

  ln -sf /home/andongni/.config/rofi/themes/dark.rasi /home/andongni/.config/rofi/current.rasi

ln -sf /home/andongni/.config/fzf/themes/dark /home/andongni/.config/fzf/current_theme

ln -sf /home/andongni/.config/newt/themes/dark /home/andongni/.config/newt/current_theme


  # 1. GTK THEME (Crucial for Hyprland)
  # Sets the "System" preference to dark
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  # (Optional) Force a specific dark GTK theme if you have one installed, e.g., Adwaita-dark
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'Trinity'
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'Matrix-Icons'
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme 'Hacker-C'

  # Alacritty: Update symlink (alacritty auto-reloads on import changes)
  ln -sf /home/andongni/.config/alacritty/themes/dark.toml /home/andongni/.config/alacritty/current.toml

  # Mako: Switch mode
  ${pkgs.mako}/bin/makoctl mode -a dark
  ${pkgs.mako}/bin/makoctl reload

  hyprctl setcursor Hacker-C 24

  '';

  # Light Mode Script
  lightModeHook = pkgs.writeShellScript "light-mode-hook" ''
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"

  ln -sf /home/andongni/.config/hypr/themes/light.conf /home/andongni/.config/hypr/themes/current.conf

  # WALLPAPER
  pkill swaybg
  ${pkgs.swaybg}/bin/swaybg -i /home/andongni/Downloads/Taiji_mandala.png -m fit -c ffffff &

  # 2. HYPRLAND BACKGROUND COLOR
  ${pkgs.hyprland}/bin/hyprctl keyword misc:background_color 0xffffff

  # Live update gaps/borders
  ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_in 4
  ${pkgs.hyprland}/bin/hyprctl keyword general:gaps_out 15
  ${pkgs.hyprland}/bin/hyprctl keyword general:border_size 2
  ${pkgs.hyprland}/bin/hyprctl keyword general:col.active_border "rgba(000000ff)"

  ln -sf /home/andongni/.config/rofi/themes/light.rasi /home/andongni/.config/rofi/current.rasi

  ln -sf /home/andongni/.config/fzf/themes/light /home/andongni/.config/fzf/current_theme

  ln -sf /home/andongni/.config/newt/themes/light /home/andongni/.config/newt/current_theme

  # 1. GTK THEME
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
  # (Optional) Force a specific light GTK theme
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface gtk-theme 'HighContrast'
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface icon-theme 'HighContrast'
  ${pkgs.glib}/bin/gsettings set org.gnome.desktop.interface cursor-theme 'Adwaita'

  echo "--color=info:#404040,prompt:#404040,pointer:#000000,marker:#000000" > /home/andongni/.config/fzf-theme

  # Alacritty: Update symlink (alacritty auto-reloads on import changes)
  ln -sf /home/andongni/.config/alacritty/themes/light.toml /home/andongni/.config/alacritty/current.toml

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
    "L+ %h/.local/share/dark-mode.d/10-nixos-hook.sh - - - - ${darkModeHook}"
    "L+ %h/.local/share/light-mode.d/10-nixos-hook.sh - - - - ${lightModeHook}"
  ];

  # Managed Assets (Themes & Icons)
  xdg.dataFile."themes/Trinity".source = ../../assets/themes/Trinity;
  xdg.dataFile."icons/Matrix-Icons".source = ../../assets/icons/Matrix-Icons;
  xdg.dataFile."icons/Hacker-C".source = ../../assets/icons/Hacker-C;
}
