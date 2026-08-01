{
  lib,
  autoPatchelfHook,
  curl,
  fetchzip,
  sqlite,
  stdenv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "codexbar";
  version = "0.46.0";

  src = fetchzip {
    url = "https://github.com/steipete/CodexBar/releases/download/v${finalAttrs.version}/CodexBarCLI-v${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-dR/7ml6dvXJXB9LTjKX8ix2C+Adjfzo+RM8diaAXLTE=";
    stripRoot = false;
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    curl
    sqlite
    stdenv.cc.cc.lib
  ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 CodexBarCLI "$out/bin/CodexBarCLI"
    ln -s "$out/bin/CodexBarCLI" "$out/bin/codexbar"

    runHook postInstall
  '';

  meta = {
    description = "CLI and local HTTP server for coding-agent usage and cost data";
    homepage = "https://github.com/steipete/CodexBar";
    downloadPage = "https://github.com/steipete/CodexBar/releases";
    license = lib.licenses.mit;
    mainProgram = "codexbar";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
