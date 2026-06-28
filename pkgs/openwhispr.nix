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
      force_shift_insert=0
      has_paste_mode=0
      for arg in "$@"; do
        case "$arg" in
          --terminal)
            has_paste_mode=1
            force_shift_insert=1
            args+=("--shift-insert")
            ;;
          --shift-insert)
            has_paste_mode=1
            args+=("--shift-insert")
            ;;
          *)
            args+=("$arg")
            ;;
        esac
      done

      if [ "$force_shift_insert" -eq 0 ] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
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
            force_shift_insert=1
            ;;
        esac
      fi

      if [ "$force_shift_insert" -eq 1 ] && [ "$has_paste_mode" -eq 0 ]; then
        args+=("--shift-insert")
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
