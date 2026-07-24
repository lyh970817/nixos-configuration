{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "cli-proxy-api";
  version = "7.2.97";

  src = fetchurl {
    url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/v${finalAttrs.version}/CLIProxyAPI_${finalAttrs.version}_linux_amd64_no-plugin.tar.gz";
    hash = "sha256-M+ruBAei9uZYt8+Wmn3xoO+Ae5JPJS8ilXLMK5n1dx8=";
  };

  sourceRoot = ".";
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 cli-proxy-api "$out/bin/cli-proxy-api"
    install -Dm644 LICENSE "$out/share/doc/cli-proxy-api/LICENSE"
    install -Dm644 README.md "$out/share/doc/cli-proxy-api/README.md"
    install -Dm644 README_CN.md "$out/share/doc/cli-proxy-api/README_CN.md"
    install -Dm644 config.example.yaml "$out/share/doc/cli-proxy-api/config.example.yaml"

    runHook postInstall
  '';

  meta = {
    description = "OpenAI, Gemini, and Claude compatible API proxy for CLI model accounts";
    homepage = "https://github.com/router-for-me/CLIProxyAPI";
    license = lib.licenses.mit;
    mainProgram = "cli-proxy-api";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
