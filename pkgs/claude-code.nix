{
  lib,
  stdenv,
  fetchzip,
  makeWrapper,
  bubblewrap,
  procps,
  socat,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "claude-code";
  version = "2.1.234";

  src = fetchzip {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-x64/-/claude-code-linux-x64-${finalAttrs.version}.tgz";
    hash = "sha256-oIM32YFxtEQWnRCzh1MjOCGF8L9sz1I+DrTgmmaEvhc=";
  };

  nativeBuildInputs = [
    makeWrapper
  ];

  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 claude "$out/bin/claude"
    install -Dm644 LICENSE.md "$out/share/doc/claude-code/LICENSE.md"
    install -Dm644 README.md "$out/share/doc/claude-code/README.md"
    install -Dm644 package.json "$out/share/doc/claude-code/package.json"

    wrapProgram "$out/bin/claude" \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            procps
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }

    runHook postInstall
  '';

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://www.npmjs.com/package/@anthropic-ai/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
