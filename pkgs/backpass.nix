{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  nodejs,
  git,
  openssh,
  acpx,
}:

# Plain ESM with no dependencies, so no npm build: the tarball is installed as
# is and bin/backpass.js is run under the pinned Node. Every model call goes
# through acpx, named by store path rather than found on PATH.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "backpass";
  version = "0.1.25";

  src = fetchzip {
    url = "https://registry.npmjs.org/backpass/-/backpass-${finalAttrs.version}.tgz";
    hash = "sha256-qsU3U43MzwNP0IYwFRut8m/CweC3CZsEwn571xkjkbs=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/backpass"
    cp -r . "$out/lib/backpass/"

    makeWrapper ${lib.getExe nodejs} "$out/bin/backpass" \
      --add-flags "$out/lib/backpass/bin/backpass.js" \
      --set-default BACKPASS_ACPX_BIN ${lib.getExe acpx} \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs
          git
          openssh
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Evidence-gated edits to AGENTS.md and skills from agent session transcripts";
    homepage = "https://github.com/kunchenguid/backpass";
    downloadPage = "https://www.npmjs.com/package/backpass";
    license = lib.licenses.mit;
    mainProgram = "backpass";
    platforms = [ "x86_64-linux" ];
  };
})
