{
  chromium,
  fetchurl,
  lib,
  makeDesktopItem,
  symlinkJoin,
  writeShellScriptBin,
}:

let
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/ph-design/zmks-studio/414ac3df4562d2dace664443285d725acca68396/src-tauri/icons/128x128.png";
    hash = "sha256-F2bD+8seyLMhYXWmwDsRcsvSsla59eqYV28DoYsurms=";
  };

  launcher = writeShellScriptBin "zmks-studio" ''
    profileDir="''${XDG_CONFIG_HOME:-$HOME/.config}/zmks-studio-chromium"
    mkdir -p "$profileDir"

    exec ${lib.getExe chromium} \
      --user-data-dir="$profileDir" \
      --class=zmks-studio \
      --app=https://zmks.phdesign.cc/ \
      "$@"
  '';

  desktopItem = makeDesktopItem {
    name = "zmks-studio";
    desktopName = "ZMKs Studio";
    comment = "Configure PH Design ZMKs keyboards";
    exec = "zmks-studio";
    inherit icon;
    categories = [ "Utility" ];
    startupWMClass = "zmks-studio";
  };
in
symlinkJoin {
  name = "zmks-studio-0.3.0-web";
  paths = [
    launcher
    desktopItem
  ];

  meta = {
    description = "PH Design web client for configuring ZMKs-powered keyboards";
    homepage = "https://zmks.phdesign.cc/";
    license = lib.licenses.asl20;
    mainProgram = "zmks-studio";
    platforms = [ "x86_64-linux" ];
  };
}
