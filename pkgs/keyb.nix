{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "keyb";
  version = "0.8.0";

  src = fetchurl {
    url = "https://github.com/kencx/keyb/releases/download/v${finalAttrs.version}/keyb-v${finalAttrs.version}-linux-amd64.tar.gz";
    hash = "sha256-nylRcwRjUVil/rs+/+DBnesfhgGh1yZFEGX+I4PJYoc=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 keyb "$out/bin/keyb"
    runHook postInstall
  '';

  meta = {
    description = "Custom hotkey cheat sheet for the terminal";
    homepage = "https://github.com/kencx/keyb";
    license = lib.licenses.mit;
    mainProgram = "keyb";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
