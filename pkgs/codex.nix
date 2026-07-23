{
  lib,
  stdenv,
  fetchzip,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.145.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${finalAttrs.version}-linux-x64.tgz";
    hash = "sha256-ZKJMWupW3X23BTGP1meEQJVOhBGfT/JY882PtiawBpU=";
  };

  dontBuild = true;
  dontStrip = true;

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
    ln -s "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex" "$out/bin/codex"

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
