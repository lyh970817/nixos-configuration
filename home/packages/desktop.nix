{ config, pkgs, ... }:

{
  # GUI applications and desktop tools
  home.packages = with pkgs; [
    waybar
    swaybg
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
    teams-for-linux
    pkgs."115browser"
    nur.repos.xddxdd.baidunetdisk
    mpv
    yandex-disk
    gvfs
    file-roller
    imagemagick
    ueberzugpp
    ffmpegthumbnailer
    openwhispr
    poppler-utils
    whisper-cpp
    adwaita-icon-theme
    gnome-themes-extra
    glib
    gsettings-desktop-schemas
    darkman
    slack
  ];
}
