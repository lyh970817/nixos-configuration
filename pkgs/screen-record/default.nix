{
  lib,
  stdenvNoCC,
  makeWrapper,
  coreutils,
  # glib provides `gio`, used by the cancel mode to trash a discarded
  # recording instead of unlinking it.
  glib,
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
          glib
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
