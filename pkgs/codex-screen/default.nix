{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  coreutils,
  darkman,
  glib,
  grim,
  hyprland,
  libnotify,
  procps,
  slurp,
}:

stdenvNoCC.mkDerivation {
  pname = "codex-screen";
  version = "0.1.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 codex_screen.py $out/libexec/codex-screen/codex_screen.py
    makeWrapper ${python3}/bin/python $out/bin/codex-screen \
      --add-flags "$out/libexec/codex-screen/codex_screen.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          darkman
          glib
          grim
          hyprland
          libnotify
          procps
          slurp
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Audited visual verification helper for Codex on Hyprland";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "codex-screen";
  };
}
