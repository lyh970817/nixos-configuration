{
  lib,
  fetchurl,
  appimageTools,
  runtimeShell,
  hyprland,
  jq,
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
      terminal_target=0
      real_has_paste_mode=0
      for arg in "$@"; do
        case "$arg" in
          --terminal)
            terminal_target=1
            ;;
          --shift-insert)
            real_has_paste_mode=1
            args+=("--shift-insert")
            ;;
          *)
            args+=("$arg")
            ;;
        esac
      done

      if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        active_window="$(
          hyprctl activewindow -j 2>/dev/null \
            | jq -r '[
                .class // "",
                .initialClass // "",
                .title // "",
                .initialTitle // ""
              ] | join("\n")' 2>/dev/null \
            | tr '[:upper:]' '[:lower:]'
        )"
        case "$active_window" in
          *alacritty* | *kitty* | *wezterm* | *foot* | *ghostty* | *terminal*)
            terminal_target=1
            ;;
        esac
      fi

      if [ "$terminal_target" -eq 1 ]; then
        sleep 0.05
        if command -v wtype >/dev/null 2>&1 \
          && wtype -M ctrl -M shift -k v -m shift -m ctrl; then
          exit 0
        fi
        if command -v ydotool >/dev/null 2>&1 \
          && ydotool key 29:1 42:1 47:1 47:0 42:0 29:0; then
          exit 0
        fi
        if [ "$real_has_paste_mode" -eq 0 ]; then
          args+=("--shift-insert")
        fi
      fi

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
    hyprland
    jq
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
