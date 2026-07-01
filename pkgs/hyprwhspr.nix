{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  python3,
  coreutils,
  dbus,
  ffmpeg,
  glib,
  gnugrep,
  gnused,
  hyprland,
  libnotify,
  pipewire,
  pulseaudio,
  which,
  wl-clipboard,
  wtype,
  ydotool,
}:

let
  pythonEnv = python3.withPackages (
    ps: with ps; [
      dbus-python
      elevenlabs
      evdev
      numpy
      psutil
      pulsectl
      pycairo
      pygobject3
      pyperclip
      pyudev
      requests
      rich
      scipy
      sounddevice
      websocket-client
    ]
  );

  runtimePath = lib.makeBinPath [
    coreutils
    dbus
    ffmpeg
    glib
    gnugrep
    gnused
    hyprland
    libnotify
    pipewire
    pulseaudio
    which
    wl-clipboard
    wtype
    ydotool
  ];
in
stdenvNoCC.mkDerivation rec {
  pname = "hyprwhspr";
  version = "1.34.1";

  src = fetchFromGitHub {
    owner = "goodroot";
    repo = "hyprwhspr";
    rev = "v${version}";
    sha256 = "0rawmq2lvlkz11pj0fk7xmar52ia2mjrzxnx3i4wpb5pg4h0a9n2";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    appdir="$out/lib/hyprwhspr"
    docdir="$out/share/doc/hyprwhspr"
    mkdir -p "$appdir" "$out/bin" "$docdir"
    cp -R bin config lib share scripts utils requirements.txt requirements-visualizer.txt "$appdir/"
    cp -R README.md LICENSE contrib docs "$docdir/"

    makeWrapper ${bash}/bin/bash "$out/bin/hyprwhspr" \
      --add-flags "$appdir/bin/hyprwhspr" \
      --set HYPRWHSPR_ROOT "$appdir" \
      --set PYTHONUNBUFFERED "1" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$appdir/lib:$appdir/lib/src"

    makeWrapper ${bash}/bin/bash "$out/bin/meeting-recorder" \
      --add-flags "$appdir/bin/meeting-recorder" \
      --set HYPRWHSPR_ROOT "$appdir" \
      --set PYTHONUNBUFFERED "1" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$appdir/lib:$appdir/lib/src"

    substituteInPlace "$appdir/bin/hyprwhspr" \
      --replace-fail 'local system_path="/usr/bin:/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/sbin"' \
        'local system_path="${pythonEnv}/bin"' \
      --replace-fail 'VENV_PYTHON="''${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv/bin/python"' \
        'VENV_PYTHON="${pythonEnv}/bin/python"'

    substituteInPlace "$appdir/bin/meeting-recorder" \
      --replace-fail 'VENV_PYTHON="''${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv/bin/python"' \
        'VENV_PYTHON="${pythonEnv}/bin/python"'

    # Nixpkgs ydotoold reports "unknown" for --version; trust the pinned package version.
    substituteInPlace "$appdir/lib/src/cli_commands.py" \
      --replace-fail '        version = "0.1.0"' '        version = "${ydotool.version}"'

    runHook postInstall
  '';

  meta = {
    description = "Native speech-to-text for Linux";
    homepage = "https://github.com/goodroot/hyprwhspr";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hyprwhspr";
  };
}
