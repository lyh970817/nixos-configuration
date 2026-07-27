{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  runtimeShell,
  brave,
  libseccomp,
  libsecret,
  glib,
}:

# Upstream publishes only an unversioned `latest` pointer, no checksum, so it
# can't be pinned. The FOD hash goes stale whenever Anthropic republishes —
# re-fetch and bump `sha256` together with `version`, taken from
# `claude-science --version` on the fetched binary. The store binary is
# read-only, so the app's own self-updater cannot work; updates come through
# this derivation.
stdenv.mkDerivation {
  pname = "claude-science";
  version = "0.1.25";

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-science/latest/linux-x64";
    sha256 = "c663367bbc7ec54e7d1e5a9102594a9e70804ed5070f5d7cd1117e665e3c376c";
  };

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    libseccomp
    libsecret
    glib
  ];

  # libseccomp/libsecret/glib are dlopen'd, not NEEDED, so autoPatchelf won't add them.
  appendRunpaths = [
    (lib.makeLibraryPath [
      libseccomp
      libsecret
      glib
    ])
  ];

  installPhase = ''
    runHook preInstall

    # The raw ELF lives in libexec; autoPatchelfHook and appendRunpaths still
    # reach it because both scan the whole output tree.
    install -Dm755 $src $out/libexec/claude-science

    # The vendored sharp bits (sharp-linux-x64-*.node, libvips-cpp.so.*) are
    # unpacked into $HOME/.claude-science/runtime at *runtime* and carry only
    # $ORIGIN RPATHs, so appendRunpaths can't reach them and a dlopen'd object
    # does not inherit the executable's DT_RUNPATH. Putting libstdc++ on
    # LD_LIBRARY_PATH for the process is what makes them loadable.
    # Do NOT set or forward TMPDIR here: the app hard-fails while creating its
    # seccomp probe directory if TMPDIR points at a path that doesn't exist.
    makeWrapper $out/libexec/claude-science $out/bin/claude-science \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}

    # `claude-science url` only talks to an already-running daemon and fails
    # otherwise; under Terminal=false that error is invisible. `serve --detached`
    # returns 0 only once the daemon is ready and is idempotent, but never opens
    # a browser — hence both, in order.
    # Upstream `claude-science open` hands the URL to xdg-open, which lands as a
    # tab in the already-running Brave. It honours no $BROWSER override and
    # prints the URL only on stderr, so drive Brave ourselves: `url` puts the
    # link alone on stdout (upstream's own idiom). That link is single-use and
    # expires in ~3 minutes, so call `url` exactly once per launch.
    # Swap --new-window for --app="$url" to get a chromeless app-style window.
    # --dangerously-no-sandbox: the app's bwrap bind allowlist is hardcoded
    # ["/usr","/lib","/lib64","/bin","/sbin","/opt","/nix"], no "/run", so on
    # NixOS bash (/run/current-system/sw/bin/bash) and nix-ld's NIX_LD
    # (/run/current-system/sw/share/nix-ld/lib/ld.so) are unreachable inside the
    # namespace: 0/20 bundled stdio connectors work sandboxed vs 20/20 with the
    # flag. Tradeoff: the daemon gets full $HOME read/write and unrestricted
    # network. Real fix is upstream binding /run.
    # Quoted heredoc: only Nix interpolates, the shell leaves the body alone.
    cat > $out/bin/claude-science-open <<'EOF'
    #!${runtimeShell}
    set -eu
    ${placeholder "out"}/bin/claude-science serve --detached --dangerously-no-sandbox
    url=$(${placeholder "out"}/bin/claude-science url)
    exec ${brave}/bin/brave --new-window "$url"
    EOF
    chmod 755 $out/bin/claude-science-open

    # No StartupWMClass: a plain `brave --new-window` window carries the shared
    # brave-browser class, so claiming it here would capture every Brave window.
    # Quoted heredoc: only Nix interpolates, the shell leaves the body alone.
    mkdir -p $out/share/applications
    cat > $out/share/applications/claude-science.desktop <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=Claude Science
    Comment=Anthropic's AI workbench for scientific research
    Exec=${placeholder "out"}/bin/claude-science-open
    Terminal=false
    Categories=Science;Education;Development;
    Keywords=claude;anthropic;ai;science;research;workbench;
    StartupNotify=false
    EOF
    chmod 444 $out/share/applications/claude-science.desktop

    runHook postInstall
  '';

  meta = {
    description = "Anthropic Claude Science workbench";
    homepage = "https://claude.com/product/claude-science";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "claude-science";
  };
}
