{
  lib,
  stdenvNoCC,
  makeWrapper,
  coreutils,
  # Pause segments the recording, so stop has to join the segments back
  # together; ffmpeg's concat demuxer under `-c copy` does that without
  # re-encoding. Headless is enough: no filters, no devices, no display.
  ffmpeg-headless,
  # glib provides `gio`, used to trash the spent segments after a successful
  # join instead of unlinking them. A cancelled recording does not go there --
  # see discard-segments.py, which deletes it for real after a verified move.
  glib,
  hyprland,
  jq,
  libnotify,
  # Runs discard-segments.py, the guarded trash-then-purge for cancel.
  python3,
  # `pw-cli` answers the one question the recorder cannot: whether the
  # mic+system mix sink exists. wl-screenrec records silence rather than
  # failing when --audio-device names something that is not there.
  pipewire,
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
    install -Dm755 discard-segments.py $out/libexec/screen-record/discard-segments.py
    patchShebangs $out/bin/screen-record
    wrapProgram $out/bin/screen-record \
      --set SCREEN_RECORD_LIBEXEC $out/libexec/screen-record \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          ffmpeg-headless
          glib
          hyprland
          jq
          libnotify
          pipewire
          python3
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
