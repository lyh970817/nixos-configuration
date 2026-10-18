{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

# The release archive plus the Chrome for Testing build its bundle.json pins
# (Vimium is already inside the archive), laid out as the upstream installer
# leaves a version directory. The binaries stay unpatched and run through
# nix-ld with the bundle's own lib/. A session needs a writable .active lock
# beside bin/, so this store copy is not run directly: see
# home/programs/termium.nix.
let
  chrome = rec {
    version = "152.0.7977.75";
    src = fetchurl {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${version}/linux64/chrome-linux64.zip";
      hash = "sha256-oW02iQY2vXIlETOyfwWCX3+SacJCWzQI+jp24Q3M2PE=";
    };
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "termium";
  version = "0.2.4";

  src = fetchurl {
    url = "https://github.com/codr1/termium/releases/download/v${finalAttrs.version}/termium-linux-amd64.tar.gz";
    hash = "sha256-H02e8rGVM9FCm+mN9gIK8vFJ7yDmhdt350AvdUT60XU=";
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/termium/browser"
    cp -a bin bundle.json fonts fonts.conf lib LICENSE node_modules notices README.md runtime server \
      "$out/lib/termium/"
    unzip -q ${chrome.src} -d "$out/lib/termium/browser"

    runHook postInstall
  '';

  meta = {
    description = "Chromium in the terminal with Vimium navigation, drawn with kitty graphics or sixel";
    homepage = "https://github.com/codr1/termium";
    license = lib.licenses.mit;
    mainProgram = "termium";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
