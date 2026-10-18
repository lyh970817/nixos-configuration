{
  lib,
  stdenvNoCC,
  fetchurl,
  jq,
  unzip,
}:

# The release archive plus the Chrome for Testing build and Vimium checkout its
# bundle.json pins, laid out as the upstream installer leaves a version
# directory. The binaries stay unpatched and run through nix-ld with the
# bundle's own lib/. A session needs a writable .active lock beside bin/, so
# this store copy is not run directly: see home/programs/termium.nix.
let
  chrome = rec {
    version = "152.0.7977.75";
    src = fetchurl {
      url = "https://storage.googleapis.com/chrome-for-testing-public/${version}/linux64/chrome-linux64.zip";
      hash = "sha256-oW02iQY2vXIlETOyfwWCX3+SacJCWzQI+jp24Q3M2PE=";
    };
  };
  vimium = rec {
    rev = "5aa29614bf1dce05e0d316f8c38722e17f9b38c3";
    src = fetchurl {
      url = "https://codeload.github.com/philc/vimium/zip/${rev}";
      name = "vimium-${rev}.zip";
      hash = "sha256-N6ZFJ1FbwFyRR/RqIyTEnTRn1t8XJu31nWDk41W51Hc=";
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

  nativeBuildInputs = [
    jq
    unzip
  ];

  sourceRoot = ".";
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/termium/browser"
    cp -a bin bundle.json fonts fonts.conf lib LICENSE node_modules notices README.md runtime server \
      "$out/lib/termium/"
    unzip -q ${chrome.src} -d "$out/lib/termium/browser"

    # The archive carries only Termium's own Vimium pages; the installer adds
    # the files bundle.json lists from the pinned checkout to both copies.
    unzip -q ${vimium.src} -d vimium
    jq -r '.dependencies[] | select(.name == "vimium") | .files | keys[]' bundle.json > vimium-files
    for dest in server/dist/extensions/vimium node_modules/termium-server/dist/extensions/vimium; do
      while IFS= read -r file; do
        install -Dm644 "vimium/vimium-${vimium.rev}/$file" "$out/lib/termium/$dest/$file"
      done < vimium-files
    done

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
