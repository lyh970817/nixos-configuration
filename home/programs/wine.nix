# Wine packages and WeChat via Wine
{ config, pkgs, lib, ... }:

let
  # Use Wine with Wayland support for Hyprland compatibility
  wine = pkgs.wineWowPackages.waylandFull;

  # WeChat launcher script
  wechat-wine = pkgs.writeShellScriptBin "wechat-wine" ''
    export WINEPREFIX="$HOME/.wine-wechat"
    export WINEARCH=win64

    # Create prefix if it doesn't exist
    if [ ! -d "$WINEPREFIX" ]; then
      echo "Creating Wine prefix for WeChat..."
      ${wine}/bin/wineboot --init
    fi

    WECHAT_EXE="$WINEPREFIX/drive_c/Program Files/Tencent/WeChat/WeChat.exe"

    if [ -f "$WECHAT_EXE" ]; then
      ${wine}/bin/wine64 "$WECHAT_EXE" "$@"
    else
      echo "WeChat not found. Please install it first:"
      echo ""
      echo "1. Download WeChat installer from: https://pc.weixin.qq.com/"
      echo "2. Run: wechat-wine-install /path/to/WeChatSetup.exe"
      echo ""
      echo "Or run the installer directly with:"
      echo "  WINEPREFIX=~/.wine-wechat wine64 /path/to/WeChatSetup.exe"
      exit 1
    fi
  '';

  # WeChat installer helper script
  wechat-wine-install = pkgs.writeShellScriptBin "wechat-wine-install" ''
    export WINEPREFIX="$HOME/.wine-wechat"
    export WINEARCH=win64

    if [ -z "$1" ]; then
      echo "Usage: wechat-wine-install /path/to/WeChatSetup.exe"
      echo ""
      echo "Download the installer from: https://pc.weixin.qq.com/"
      exit 1
    fi

    if [ ! -f "$1" ]; then
      echo "Error: File not found: $1"
      exit 1
    fi

    echo "Creating Wine prefix for WeChat..."
    ${wine}/bin/wineboot --init

    echo "Installing WeChat..."
    ${wine}/bin/wine64 "$1"

    echo ""
    echo "Installation complete. Run 'wechat-wine' to start WeChat."
  '';
in
{
  home.packages = [
    wine
    pkgs.winetricks
    wechat-wine
    wechat-wine-install
  ];

  # Desktop entry for WeChat via Wine
  xdg.desktopEntries.wechat-wine = {
    name = "WeChat (Wine)";
    comment = "WeChat messaging via Wine";
    exec = "wechat-wine";
    icon = "wechat";
    terminal = false;
    categories = [ "Network" "InstantMessaging" ];
  };
}
