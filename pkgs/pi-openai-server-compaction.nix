{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchzip,
}:

let
  # pi's jiti loader virtualizes only pi's own packages, so `ws` has to resolve
  # by ordinary Node resolution from the extension directory. ws has no runtime
  # dependencies, so vendoring the published tarball verbatim is sufficient.
  ws = fetchzip {
    url = "https://registry.npmjs.org/ws/-/ws-8.21.1.tgz";
    hash = "sha256-OE7z3w8GvhfcrrKQ+PPBr5gujYuLX7oFMPQA+U0K4lA=";
  };
in

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-openai-server-compaction";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "algal";
    repo = "pi-openai-server-compaction";
    rev = "8a3de2f3b0c178fdd6f73f2f94172dfc3943e466";
    hash = "sha256-HFzG+GMriPhoMinjji+3sklQ7Nq0yRHCz/t9Re/TksU=";
  };

  dontBuild = true;

  # The extension entrypoint is raw TypeScript loaded at runtime by pi's jiti
  # loader, so the tree is installed as-is with no compile step.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r src "$out/src"
    install -Dm644 package.json "$out/package.json"

    mkdir -p "$out/node_modules/ws"
    cp -r ${ws}/. "$out/node_modules/ws/"
    chmod -R u+w "$out/node_modules/ws"

    for doc in README.md ARCHITECTURE.md CHANGELOG.md LICENSE.md; do
      install -Dm644 "$doc" "$out/share/doc/pi-openai-server-compaction/$doc"
    done

    runHook postInstall
  '';

  meta = {
    description = "pi extension that offloads context compaction to the OpenAI server";
    homepage = "https://github.com/algal/pi-openai-server-compaction";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
