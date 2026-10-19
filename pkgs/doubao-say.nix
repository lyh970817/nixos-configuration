{
  lib,
  python3Packages,
  fetchFromGitHub,
  wrapGAppsHook4,
  gobject-introspection,
  gtk4,
  gtk4-layer-shell,
  webkitgtk_6_0,
  glib-networking,
  coreutils,
  pipewire,
  wl-clipboard,
  wtype,
}:

python3Packages.buildPythonApplication rec {
  pname = "doubao-say";
  version = "1.8.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "quanru";
    repo = "doubao-say";
    rev = "v${version}";
    hash = "sha256-ELAgPVIoP4SnlsYZAUj6vXv8hweTbvmfWXAEWDCeANs=";
  };

  # Terminal paste (Ctrl+Shift+V) is chosen by exact window class; add the
  # per-instance kitty/foot classes from home/programs/kitty.nix and foot.nix.
  postPatch = ''
    substituteInPlace src/doubao_input/inject/injector.py \
      --replace-fail '"foot", "footclient", "kitty",' \
        '"foot", "footclient", "kitty", "kitty-float", "kitty-main", "foot-float", "foot-main",'
  '';

  build-system = [ python3Packages.setuptools ];

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
  ];

  buildInputs = [
    gtk4
    gtk4-layer-shell
    webkitgtk_6_0
    glib-networking
  ];

  dependencies = with python3Packages; [
    pygobject3
    pyjwt
    cryptography
    websockets
    sounddevice
    evdev
  ];

  postInstall = ''
    install -Dm644 packaging/store/md.lifeos.DoubaoSay.desktop \
      $out/share/applications/md.lifeos.DoubaoSay.desktop
    install -Dm644 src/doubao_input/resources/logo-128.png \
      $out/share/icons/hicolor/128x128/apps/md.lifeos.DoubaoSay.png
  '';

  # The app finds gtk4-layer-shell with ctypes.util.find_library, which cannot
  # see the store, and re-execs itself with it preloaded; preload it here and
  # mark the re-exec done.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=(
      "''${gappsWrapperArgs[@]}"
      --prefix LD_PRELOAD : ${gtk4-layer-shell}/lib/libgtk4-layer-shell.so
      --set DOUBAO_LAYER_SHELL_PRELOADED 1
      --prefix PATH : ${
        lib.makeBinPath [
          # wl-copy runs `cat` to buffer its input.
          coreutils
          pipewire
          wl-clipboard
          wtype
        ]
      }
    )
  '';

  # The suite needs a live GTK/WebKit session.
  doCheck = false;

  meta = {
    description = "Global voice input for Linux/Wayland backed by Doubao ASR";
    homepage = "https://github.com/quanru/doubao-say";
    license = lib.licenses.mit;
    mainProgram = "doubao-say";
    platforms = lib.platforms.linux;
  };
}
