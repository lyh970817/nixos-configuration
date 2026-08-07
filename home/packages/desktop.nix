{ config, pkgs, ... }:

{
  # GUI applications and desktop tools
  home.packages = with pkgs; [
    waybar
    swaybg
    brightnessctl
    playerctl
    brave
    chromium
    libnotify
    calibre
    sioyek
    libreoffice-fresh
    bitwarden-desktop
    bitwarden-cli
    wtype
    zoom-us
    wemeet
    teams-for-linux
    pkgs."115browser"
    nur.repos.xddxdd.baidunetdisk
    mpv
    yandex-disk
    gvfs
    file-roller
    imagemagick
    imv
    ueberzugpp
    ffmpegthumbnailer
    poppler-utils
    whisper-cpp
    adwaita-icon-theme
    gnome-themes-extra
    # Dark-mode icon theme; Adwaita above is its declared Inherits fallback.
    matrix-icons
    glib
    gsettings-desktop-schemas
    darkman
    slack
  ];
}
