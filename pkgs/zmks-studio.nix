{
  appimageTools,
  fetchurl,
  lib,
}:

let
  pname = "zmks-studio";
  version = "0.3.0";

  src = fetchurl {
    url = "https://github.com/ph-design/zmks-studio/releases/download/v${version}/ZMKs.Studio_${version}_amd64.AppImage";
    hash = "sha256-IWirntU0lQwENQZWIoon87ixOOa/Xsr3QuTUaxWwfYY=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 \
      "${appimageContents}/ZMKs Studio.desktop" \
      "$out/share/applications/zmks-studio.desktop"
    cp -r "${appimageContents}/usr/share/icons" "$out/share/"
  '';

  meta = {
    description = "PH Design client for configuring ZMKs-powered keyboards";
    homepage = "https://github.com/ph-design/zmks-studio";
    license = lib.licenses.asl20;
    mainProgram = "zmks-studio";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
