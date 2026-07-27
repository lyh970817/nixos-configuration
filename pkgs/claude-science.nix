{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libseccomp,
  libsecret,
  glib,
}:

# Upstream publishes only an unversioned `latest` pointer, no checksum, so it
# can't be pinned. The FOD hash goes stale whenever Anthropic republishes —
# re-fetch and bump `sha256` together with `version`, taken from
# `claude-science --version` on the fetched binary. The store binary is
# read-only, so the app's own self-updater cannot work; updates come through
# this derivation.
stdenv.mkDerivation {
  pname = "claude-science";
  version = "0.1.25";

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-science/latest/linux-x64";
    sha256 = "c663367bbc7ec54e7d1e5a9102594a9e70804ed5070f5d7cd1117e665e3c376c";
  };

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  buildInputs = [
    libseccomp
    libsecret
    glib
  ];

  # libseccomp/libsecret/glib are dlopen'd, not NEEDED, so autoPatchelf won't add them.
  appendRunpaths = [
    (lib.makeLibraryPath [
      libseccomp
      libsecret
      glib
    ])
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/bin/claude-science

    runHook postInstall
  '';

  meta = {
    description = "Anthropic Claude Science workbench";
    homepage = "https://claude.com/product/claude-science";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-science";
  };
}
