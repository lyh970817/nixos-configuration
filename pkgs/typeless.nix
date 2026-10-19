{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
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
  libnotify,
  libopus,
  libpulseaudio,
  libsecret,
  libuuid,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemd,
  vulkan-loader,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxscrnsaver,
  libxtst,
  acl,
  procps,
  wl-clipboard,
  xdg-utils,
}:

# Typeless's official Linux build: an Electron app whose native helpers read the
# hotkey from evdev and type through /dev/uinput.
stdenv.mkDerivation rec {
  pname = "typeless";
  version = "2.2.0";

  src = fetchurl {
    url = "https://typeless-static.com/desktop-release/Typeless-${version}-x64.deb";
    hash = "sha256-1zkm24+V1m6p/HSOzwzHCjcNw0xBv9sjvPeHO1RlAnU=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
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
    libnotify
    libopus
    libpulseaudio
    libsecret
    libuuid
    libxkbcommon
    nspr
    nss
    pango
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxscrnsaver
    libxtst
    libxcb
  ];

  # Loaded with dlopen, so autoPatchelf cannot see them.
  runtimeDependencies = [
    libGL
    libpulseaudio
    systemd
    vulkan-loader
  ];

  # Only its IBus input-method engine links libibus; without IBus Typeless
  # types through uinput or pastes instead.
  autoPatchelfIgnoreMissingDeps = [ "libibus-1.0.so.5" ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt $out/bin
    cp -r opt/Typeless $out/opt/
    cp -r usr/share $out/share
    rm -rf $out/share/doc
    substituteInPlace $out/share/applications/typeless.desktop \
      --replace-fail 'Exec=/opt/Typeless/typeless' 'Exec=typeless'

    # chrome-sandbox would need setuid root; Electron runs unsandboxed
    # instead, as the AppImage builds of these apps do. Native Wayland with
    # DISPLAY unset: its X11 helper hits BadWindow on Wayland surfaces
    # (github.com/howiehu/typeless-omarchy, bin/typeless-omarchy).
    makeWrapper $out/opt/Typeless/typeless $out/bin/typeless \
      --unset DISPLAY \
      --add-flags "--no-sandbox --ozone-platform=wayland" \
      --prefix PATH : ${
        lib.makeBinPath [
          acl
          procps
          wl-clipboard
          xdg-utils
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Typeless AI voice dictation";
    homepage = "https://www.typeless.com";
    license = lib.licenses.unfree;
    mainProgram = "typeless";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
