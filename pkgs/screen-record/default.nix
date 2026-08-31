{
  lib,
  stdenvNoCC,
  makeWrapper,
  coreutils,
  # Pause segments the recording, so stop has to join the segments back
  # together; ffmpeg's concat demuxer under `-c copy` does that without
  # re-encoding. Headless is enough: no filters, no devices, no display.
  ffmpeg-headless,
  # glib provides `gio`, used to trash a discarded recording, and the spent
  # segments after a successful join, instead of unlinking them.
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
          ffmpeg-headless
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
    description = "Start, pause, resume and save a wl-screenrec recording on Hyprland";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "screen-record";
  };
}
