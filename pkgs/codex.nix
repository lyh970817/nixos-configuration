{
  lib,
  stdenv,
  fetchzip,
  makeWrapper,
  alsa-lib,
  pipewire,
  disableApps ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.155.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${finalAttrs.version}-linux-x64.tgz";
    hash = "sha256-z7WU/4bf3WXfeXxwXlhmSnoZzDEvJDFAuN2WRwwKcFc=";
  };

  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/codex"
    cp -r vendor "$out/lib/codex/vendor"
    chmod +x "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex-code-mode-host" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/codex-path/rg" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/codex-resources/bwrap" \
      "$out/lib/codex/vendor/x86_64-unknown-linux-musl/codex-resources/zsh/bin/zsh"

    mkdir -p "$out/bin"
    makeWrapper "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex" "$out/bin/codex" \
      --unset COLORTERM ${lib.optionalString disableApps ''--add-flags "--disable apps"''}

    # The /voice helper links alsa-lib statically with /usr paths baked in, and
    # that alsa-lib predates the `libs` field NixOS uses in /etc/alsa/conf.d, so
    # it gets a private alsa.conf routing the default device to PipeWire. Codex
    # launches it with an environment allowlist, so the variable has to be set
    # by a wrapper around the helper itself. Its libraries resolve relative to
    # the executable, so the real binary stays a sibling of lib/.
    voice="$out/lib/codex/vendor/x86_64-unknown-linux-musl/codex-resources/voice"
    mkdir -p "$voice/libexec" "$voice/alsa/conf.d"
    mv "$voice/bin/codex-voice-host" "$voice/libexec/codex-voice-host"
    sed -e "s|\"/var/lib/alsa/conf.d\"|\"$voice/alsa/conf.d\"|" \
      -e '\|"/usr/etc/alsa/conf.d"|d' \
      -e '\|"/etc/alsa/conf.d"|d' \
      ${alsa-lib}/share/alsa/alsa.conf > "$voice/alsa/alsa.conf"
    cp ${pipewire}/share/alsa/alsa.conf.d/50-pipewire.conf \
      ${pipewire}/share/alsa/alsa.conf.d/99-pipewire-default.conf \
      "$voice/alsa/conf.d/"
    cat > "$voice/alsa/conf.d/49-pipewire-modules.conf" <<EOF
    pcm_type.pipewire { lib "${pipewire}/lib/alsa-lib/libasound_module_pcm_pipewire.so" }
    ctl_type.pipewire { lib "${pipewire}/lib/alsa-lib/libasound_module_ctl_pipewire.so" }
    EOF
    makeWrapper "$voice/libexec/codex-voice-host" "$voice/bin/codex-voice-host" \
      --set ALSA_CONFIG_PATH "$voice/alsa/alsa.conf"

    install -Dm644 README.md "$out/share/doc/codex/README.md"
    install -Dm644 package.json "$out/share/doc/codex/package.json"

    runHook postInstall
  '';

  meta = {
    description = "Lightweight coding agent from OpenAI that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    downloadPage = "https://www.npmjs.com/package/@openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
})
