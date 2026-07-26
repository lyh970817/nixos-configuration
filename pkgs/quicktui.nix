{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  ncurses,
  procps,
  tmux,
}:

# QuickTUI is closed source: the GitHub repo only carries the website and the
# prebuilt release binaries, so the server is fetched as a release asset. The
# asset is a statically linked Go executable (no PT_INTERP), which is why no
# autoPatchelfHook or FHS wrapper is involved.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "quicktui";
  version = "20260725-02";

  src = fetchurl {
    url = "https://github.com/dualface/quicktui/releases/download/${finalAttrs.version}/quicktui-server-linux-amd64";
    hash = "sha256-yTUpgLhm5jss7IjdSTt8iKvxxh99os7zW8tZAv8K2+w=";
  };

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/quicktui-server"

    # tmux 3.2+ is the core runtime dependency; the server also shells out to
    # `ps` (sweeping orphaned tmux attachments) and `infocmp` (validating TERM).
    # `locale` is deliberately not pinned: its absence only skips an advisory
    # check on an already-validated locale name.
    #
    # The paths are appended rather than prefixed so an interactive session
    # keeps using its own tmux (client and server must agree on the protocol
    # version); the pinned copies are a fallback for contexts such as systemd
    # user units with a minimal PATH.
    wrapProgram "$out/bin/quicktui-server" \
      --suffix PATH : ${
        lib.makeBinPath [
          tmux
          procps
          ncurses
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Remote terminal server exposing tmux sessions over a browser or the QuickTUI mobile app";
    homepage = "https://quicktui.ai/";
    license = lib.licenses.unfree;
    mainProgram = "quicktui-server";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
