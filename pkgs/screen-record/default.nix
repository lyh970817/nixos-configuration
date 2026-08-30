{
  lib,
  stdenvNoCC,
  makeWrapper,
  coreutils,
  hyprland,
  jq,
  libnotify,
  slurp,
  wl-screenrec,
}:

stdenvNoCC.mkDerivation {
  pname = "screen-record";
  version = "0.1.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 screen-record.sh $out/bin/screen-record
    patchShebangs $out/bin/screen-record
    wrapProgram $out/bin/screen-record \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          hyprland
          jq
          libnotify
          slurp
          wl-screenrec
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Toggle a wl-screenrec screen or region recording on Hyprland";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "screen-record";
  };
}
