{
  lib,
  stdenv,
  fetchzip,
  makeWrapper,
  disableApps ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.148.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${finalAttrs.version}-linux-x64.tgz";
    hash = "sha256-syI0rh/FLIZWwotZ0XmRBpP5WzF8DjrQ+1TshbcvBLs=";
  };

  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/codex"
    cp -r vendor "$out/lib/codex/vendor"
    chmod +x "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex-code-mode-host" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/codex-path/rg" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/codex-resources/bwrap" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/codex-resources/zsh/bin/zsh"

    mkdir -p "$out/bin"
    makeWrapper "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex" "$out/bin/codex" \
      --unset COLORTERM ${lib.optionalString disableApps ''--add-flags "--disable apps"''}

    install -Dm644 README.md "$out/share/doc/codex/README.md"
    install -Dm644 package.json "$out/share/doc/codex/package.json"

    runHook postInstall
  '';

  meta = {
    description = "Lightweight coding agent from OpenAI that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    downloadPage = "https://www.npmjs.com/package/@openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
