{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  coreutils,
  glib,
  grim,
  hyprland,
  libnotify,
  mako,
  procps,
  slurp,
}:

stdenvNoCC.mkDerivation {
  pname = "screen-verify";
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
    install -Dm755 screen_verify.py $out/libexec/screen-verify/screen_verify.py
    cp -r screen_verify_lib $out/libexec/screen-verify/screen_verify_lib
    makeWrapper ${python3}/bin/python $out/bin/screen-verify \
      --add-flags "$out/libexec/screen-verify/screen_verify.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          glib
          grim
          hyprland
          libnotify
          mako
          procps
          slurp
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Audited visual verification helper for Hyprland";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "screen-verify";
  };
}
