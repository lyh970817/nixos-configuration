# Wine support for running Windows applications
{ config, pkgs, lib, ... }:

{
  # Enable nix-ld for running unpatched binaries (Bottles runners)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    fuse3
    icu
    zstd
    nss
    openssl
    curl
    expat
    libxml2
    libxslt
    glib
    gtk3
    pango
    cairo
    freetype
    fontconfig
    dbus
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cups
    libdrm
    libxkbcommon
    mesa
    nspr
    xorg.libX11
    xorg.libXcomposite
    xorg.libXcursor
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXi
    xorg.libXrandr
    xorg.libXrender
    xorg.libXScrnSaver
    xorg.libXtst
    xorg.libxcb
  ];
}
