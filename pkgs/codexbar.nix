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
  version = "0.70.0";

  src = fetchzip {
    url = "https://github.com/steipete/CodexBar/releases/download/v${finalAttrs.version}/CodexBarCLI-v${finalAttrs.version}-linux-x86_64.tar.gz";
    hash = "sha256-BSEJBLvDai4vQyKw29D6DCHeQROtlQu0N0GhbZMdbCw=";
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

    # Provider plugins load from the resource bundle beside the resolved
    # executable, so the two stay together and bin/ only holds symlinks.
    install -Dm755 CodexBarCLI "$out/libexec/codexbar/CodexBarCLI"
    cp -r CodexBar_CodexBarCore.bundle "$out/libexec/codexbar/"
    mkdir -p "$out/bin"
    ln -s "$out/libexec/codexbar/CodexBarCLI" "$out/bin/CodexBarCLI"
    ln -s "$out/libexec/codexbar/CodexBarCLI" "$out/bin/codexbar"

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
