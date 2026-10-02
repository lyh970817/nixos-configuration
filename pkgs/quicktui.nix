{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  ncurses,
  procps,
}:

# QuickTUI is closed source: the GitHub repo only carries the website and the
# prebuilt release binaries, so the server is fetched as a release asset. The
# asset is a statically linked Go executable (no PT_INTERP), which is why no
# autoPatchelfHook or FHS wrapper is involved.
#
# This tracks the "server2" line (tags `server2-YYYYMMDD-NN`, update channel
# server2). The legacy `YYYYMMDD-NN` line was discontinued on 2026-09-26. The
# hash is the published `quicktui-server-linux-amd64.sha256` beside the asset.
#
# Never use the binary's self-management commands (`upgrade`, `service
# install|uninstall|restart`, `config set`, which restarts the service): they
# would write to the read-only store path or register a systemd unit competing
# with the one in home/programs/quicktui.nix. Bump the version here instead.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "quicktui";
  version = "20260929-02";

  src = fetchurl {
    url = "https://github.com/dualface/quicktui/releases/download/server2-${finalAttrs.version}/quicktui-server-linux-amd64";
    hash = "sha256-tG3aqxmq/NY4pesZrsigQDPRsaI3M8akcDaxvXDZHDk=";
  };

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/quicktui-server"

    # The session backend (Herdr or tmux) is deliberately not pinned: the
    # server must drive the user's own multiplexer, whose client and server have
    # to agree on the protocol, so it is chosen per deployment through
    # `herdr_bin` / `tmux_bin` in config.toml or found on PATH. The server still
    # shells out to `ps` and `infocmp` (validating TERM); those are appended as a
    # fallback for contexts such as systemd user units with a minimal PATH.
    # `locale` is not pinned: its absence only skips an advisory check.
    wrapProgram "$out/bin/quicktui-server" \
      --suffix PATH : ${
        lib.makeBinPath [
          procps
          ncurses
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Remote terminal server exposing Herdr or tmux sessions to the QuickTUI mobile app";
    homepage = "https://quicktui.ai/";
    license = lib.licenses.unfree;
    mainProgram = "quicktui-server";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
