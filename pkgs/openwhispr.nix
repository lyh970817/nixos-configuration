{
  lib,
  fetchurl,
  appimageTools,
  runtimeShell,
  ydotool,
  wtype,
  xdotool,
}:

let
  pname = "openwhispr";
  version = "1.7.3";
  src = fetchurl {
    url = "https://github.com/OpenWhispr/openwhispr/releases/download/v${version}/OpenWhispr-${version}-linux-x86_64.AppImage";
    hash = "sha256-590A9noHhuHtBt0lEGBoohS8SJItOtD9xUMsDLAwa4E=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
    postExtract = ''
            fast_paste="$out/resources/bin/linux-fast-paste"
            mv "$fast_paste" "$fast_paste.real"
            cat > "$fast_paste" <<'EOF'
      #!${runtimeShell}
      args=()
      for arg in "$@"; do
        case "$arg" in
          --terminal)
            # Codex uses Ctrl+V for image paste. OpenWhispr's terminal mode can
            # arrive as Ctrl+V in Codex, so force the terminal-safe paste shortcut.
            args+=("--shift-insert")
            ;;
          *)
            args+=("$arg")
            ;;
        esac
      done
      exec "$(dirname "$0")/linux-fast-paste.real" "''${args[@]}"
      EOF
            chmod +x "$fast_paste"
    '';
  };
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = appimageContents;

  extraPkgs = pkgs: [
    ydotool
    wtype
    xdotool
  ];

  profile = ''
    export YDOTOOL_SOCKET=/tmp/.ydotool_socket
  '';

  meta = with lib; {
    description = "Privacy-first desktop voice dictation and transcription app";
    homepage = "https://openwhispr.com";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "openwhispr";
  };
}
