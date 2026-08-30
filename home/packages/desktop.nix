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
    zmks-studio
    pkgs."115browser"
    nur.repos.xddxdd.baidunetdisk
    mpv
    yandex-disk
    gvfs
    file-roller
    imagemagick
    imv
    ffmpegthumbnailer
    poppler-utils
    whisper-cpp
    adwaita-icon-theme
    gnome-themes-extra
    # Dark-mode icon theme; Adwaita above is its declared Inherits fallback.
    matrix-icons
    # Dark-mode cursor theme. It has to be in the profile, not just named by
    # gsettings: a cursor-theme value that is not on the icon search path
    # resolves to nothing and falls back silently.
    bibata-vt220-cursors
    # The other two variants from the cursor design document, installed only so
    # they can be compared live against the one above. Nothing points at them;
    # drop these two lines once a variant has been chosen.
    bibata-vt220-cursors-darker
    bibata-vt220-cursors-muted
    glib
    gsettings-desktop-schemas
    slack
    # Windows apps (e.g. Mplus) via a 64+32-bit wine.
    wineWowPackages.stable
    winetricks
  ];
}
