{ config, pkgs, ... }:

{
  # GUI applications and desktop tools
  home.packages = with pkgs; [
    waybar
    alacritty
    rofi
    swaybg
    brave
    mako
    libnotify
    calibre
    sioyek
    libreoffice-fresh
    bitwarden-desktop
    bitwarden-cli
    wtype
    zoom-us
    teams-for-linux
    mpv
    yandex-disk
    gvfs
    file-roller
    imagemagick
    ueberzugpp
    ffmpegthumbnailer
    poppler
    adwaita-icon-theme
    gnome-themes-extra
    arc-theme
    paper-gtk-theme
    dconf-editor
    glib
    gsettings-desktop-schemas
    darkman
  ];
}
