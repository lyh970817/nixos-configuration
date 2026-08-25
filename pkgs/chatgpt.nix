{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  bubblewrap,
  coreutils,
  dpkg,
  glibc,
  makeShellWrapper,
  makeDesktopItem,
  symlinkJoin,
  wrapGAppsHook3,
  writeShellScriptBin,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  graphite2,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libnotify,
  libusb1,
  libxkbcommon,
  nspr,
  nss,
  openssl,
  pango,
  systemdLibs,
  xdg-utils,
  xorg,
}:

let
  chatgpt-unwrapped = stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "chatgpt";
    version = "26.818.61809";

    src = fetchurl {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb";
      hash = "sha256-G7piptvS1Jl1xihQ2O3arWBdoZNVexlJgiJeVrGUGJE=";
    };

    nativeBuildInputs = [
      autoPatchelfHook
      dpkg
      makeShellWrapper
      wrapGAppsHook3
    ];

    buildInputs = [
      (lib.getLib stdenv.cc.cc)
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      graphite2
      gtk3
      libdrm
      libgbm
      libGL
      libnotify
      libusb1
      libxkbcommon
      nspr
      nss
      openssl
      pango
      systemdLibs
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      xorg.libxcb
    ];

    dontBuild = true;
    dontStrip = true;

    # The bundle includes unused Qt desktop-integration shims and musl native
    # modules alongside the glibc modules selected on this platform.
    autoPatchelfIgnoreMissingDeps = [
      "libQt5*.so.*"
      "libQt6*.so.*"
      "libc.musl-x86_64.so.1"
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib" "$out/libexec"
      cp -a usr/lib/chatgpt "$out/lib/chatgpt"
      cp -a usr/share "$out/share"

      makeShellWrapper "$out/lib/chatgpt/ChatGPT" "$out/libexec/chatgpt" \
        --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}

      substituteInPlace "$out/share/applications/chatgpt.desktop" \
        --replace-fail "Exec=chatgpt %U" "Exec=chatgpt --class=chatgpt %U" \
        --replace-fail "StartupNotify=true" $'StartupNotify=true\nStartupWMClass=chatgpt'

      runHook postInstall
    '';

    meta = {
      description = "Official ChatGPT desktop application from OpenAI";
      homepage = "https://openai.com/chatgpt/desktop/";
      license = lib.licenses.unfree;
      mainProgram = "chatgpt";
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
    };
  });

  makeLauncher =
    {
      name,
      stateName,
      windowClass,
    }:
    writeShellScriptBin name ''
      runtimeDir="''${XDG_RUNTIME_DIR:-/run/user/$(${lib.getExe' coreutils "id"} -u)}"

      export CODEX_HOME="$HOME/.${stateName}"
      export XDG_CONFIG_HOME="$HOME/.config/${stateName}"
      export XDG_DATA_HOME="$HOME/.local/share/${stateName}"
      export XDG_CACHE_HOME="$HOME/.cache/${stateName}"
      export CODEX_ELECTRON_USER_DATA_PATH="$XDG_CONFIG_HOME/Codex"

      bwrapArgs=(
        --die-with-parent
        --ro-bind / /
        --dev-bind /dev /dev
        --proc /proc
        --bind "$HOME" "$HOME"
        --bind /tmp /tmp
        --tmpfs /usr
        --dir /usr/bin
        --ro-bind ${lib.getExe' glibc.bin "ldd"} /usr/bin/ldd
      )

      if [[ -d "$runtimeDir" ]]; then
        bwrapArgs+=(--bind "$runtimeDir" "$runtimeDir")
      fi

      exec ${lib.getExe bubblewrap} "''${bwrapArgs[@]}" \
        ${chatgpt-unwrapped}/libexec/chatgpt --class=${windowClass} "$@"
    '';

  launcher = makeLauncher {
    name = "chatgpt";
    stateName = "codex-desktop";
    windowClass = "chatgpt";
  };

  orchestratorLauncher = makeLauncher {
    name = "chatgpt-orchestrator";
    stateName = "codex-desktop-orchestrator";
    windowClass = "chatgpt-orchestrator";
  };

  orchestratorDesktopItem = makeDesktopItem {
    name = "chatgpt-orchestrator";
    desktopName = "ChatGPT Orchestrator";
    comment = "ChatGPT Desktop with the Codex orchestrator configuration";
    exec = "chatgpt-orchestrator %U";
    icon = "chatgpt";
    categories = [ "Development" ];
    startupNotify = true;
    startupWMClass = "chatgpt-orchestrator";
    terminal = false;
  };
in
symlinkJoin {
  name = "chatgpt-${chatgpt-unwrapped.version}";
  paths = [
    chatgpt-unwrapped
    launcher
    orchestratorLauncher
    orchestratorDesktopItem
  ];

  inherit (chatgpt-unwrapped) meta;
  passthru.unwrapped = chatgpt-unwrapped;
}
