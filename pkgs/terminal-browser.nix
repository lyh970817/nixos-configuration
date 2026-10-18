{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemdLibs,
  xorg,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "terminal-browser";
  version = "0.13.4";

  src = fetchurl {
    url = "https://terminal-browser.sh/install/dl/stable/v${finalAttrs.version}/terminal-browser-linux-x64.tar.gz";
    hash = "sha256-YnfaqrqxZxGrPxlhzf+tnvrF5wrFXVB24shkltZJ06Q=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libxkbcommon
    nspr
    nss
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

  # Chromium dlopens these for GPU offscreen rendering and device discovery.
  runtimeDependencies = [
    libGL
    systemdLibs
  ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/bin"
    cp -a . "$out/lib/terminal-browser"

    # Replaces the upstream launcher: the store copy is pinned here, so
    # `upgrade` (which reinstalls into ~/.local/share via curl | bash) is
    # refused. Telemetry and crash reports default to off.
    cat > "$out/bin/terminal-browser" <<EOF
    #!${stdenv.shell}
    if [ "\''${1:-}" = upgrade ]; then
      echo "terminal-browser is pinned in pkgs/terminal-browser.nix; bump it there and rebuild." >&2
      exit 1
    fi
    export TERMINAL_BROWSER_DIST_ROOT="$out/lib/terminal-browser"
    export TERMINAL_BROWSER_NO_TELEMETRY="\''${TERMINAL_BROWSER_NO_TELEMETRY:-1}"
    export ELECTRON_RUN_AS_NODE=1
    exec "$out/lib/terminal-browser/electron/pixel" "$out/lib/terminal-browser/cli/dist/main.js" "\$@"
    EOF
    chmod +x "$out/bin/terminal-browser"

    runHook postInstall
  '';

  meta = {
    description = "A real Chromium browser inside the terminal, drawn with the kitty graphics protocol";
    homepage = "https://github.com/zenbu-labs/terminal-browser";
    license = lib.licenses.mit;
    mainProgram = "terminal-browser";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
