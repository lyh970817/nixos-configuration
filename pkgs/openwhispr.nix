{
  lib,
  fetchurl,
  writeShellApplication,
  appimage-run,
  ydotool,
  wtype,
  xdotool,
}:

let
  version = "1.7.3";
  appimage = fetchurl {
    url = "https://github.com/OpenWhispr/openwhispr/releases/download/v${version}/OpenWhispr-${version}-linux-x86_64.AppImage";
    hash = "sha256-590A9noHhuHtBt0lEGBoohS8SJItOtD9xUMsDLAwa4E=";
  };
in
writeShellApplication {
  name = "openwhispr";
  runtimeInputs = [
    appimage-run
    ydotool
    wtype
    xdotool
  ];
  text = ''
    export YDOTOOL_SOCKET=/run/ydotoold/socket
    exec appimage-run ${appimage} "$@"
  '';

  meta = with lib; {
    description = "Privacy-first desktop voice dictation and transcription app";
    homepage = "https://openwhispr.com";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "openwhispr";
  };
}
