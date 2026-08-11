{
  lib,
  stdenv,
  fetchzip,
  makeWrapper,
  disableApps ? true,
}:

let
  # Keep this allow-list synchronized with the 0.147 root, resume, and fork
  # clap grammar. Unknown options fail closed so non-TUI routes never inherit
  # the presentation-only environment override.
  launcher = builtins.toFile "codex-launcher" ''
    #!${stdenv.shell}

    is_interactive_tui() {
      [ -t 0 ] && [ -t 1 ] || return 1

      route=root
      positionals=0
      parse_options=true
      while [ "$#" -gt 0 ]; do
        argument=$1
        shift

        if [ "$parse_options" = true ]; then
          case "$argument" in
            --)
              parse_options=false
              continue
              ;;
            -h|--help|-V|--version)
              return 1
              ;;
            -c|-i|-m|-p|-s|-C|-a|--config|--enable|--disable|--remote|--remote-auth-token-env|--image|--model|--local-provider|--profile|--sandbox|--cd|--add-dir|--ask-for-approval)
              [ "$#" -gt 0 ] || return 1
              shift
              continue
              ;;
            -c?*|-i?*|-m?*|-p?*|-s?*|-C?*|-a?*)
              continue
              ;;
            --config=*|--enable=*|--disable=*|--remote=*|--remote-auth-token-env=*|--image=*|--model=*|--local-provider=*|--profile=*|--sandbox=*|--cd=*|--add-dir=*|--ask-for-approval=*)
              [ -n "''${argument#*=}" ] || return 1
              continue
              ;;
            --strict-config|--oss|--approve-for-me|--dangerously-bypass-approvals-and-sandbox|--dangerously-bypass-hook-trust|--search|--no-alt-screen|--psp|--yolo)
              continue
              ;;
            --last|--all)
              [ "$route" = resume ] || [ "$route" = fork ] || return 1
              continue
              ;;
            --include-non-interactive)
              [ "$route" = resume ] || return 1
              continue
              ;;
            -*)
              return 1
              ;;
          esac
        fi

        if [ "$route" = root ] && [ "$positionals" -eq 0 ]; then
          case "$argument" in
            resume|fork)
              route=$argument
              continue
              ;;
            exec|e|review|login|logout|mcp|plugin|mcp-server|app-server|remote-control|completion|update|doctor|sandbox|debug|execpolicy|apply|a|archive|delete|unarchive|cloud|responses-api-proxy|stdio-to-uds|exec-server|features|help)
              return 1
              ;;
          esac
        fi

        positionals=$((positionals + 1))
        case "$route" in
          root)
            [ "$positionals" -le 1 ] || return 1
            ;;
          resume|fork)
            [ "$positionals" -le 2 ] || return 1
            ;;
        esac
      done
    }

    if is_interactive_tui "$@"; then
      export NO_COLOR=1
    fi
    exec @codex@ "$@"
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "codex";
  version = "0.147.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${finalAttrs.version}-linux-x64.tgz";
    hash = "sha256-i4BAS8nbgTD2+4pEFnexq9+p4WKgfTDuJf16a6ChpL4=";
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

    mkdir -p "$out/bin" "$out/libexec"
    makeWrapper "$out/lib/codex/vendor/x86_64-unknown-linux-musl/bin/codex" "$out/libexec/codex" \
      --unset COLORTERM ${lib.optionalString disableApps ''--add-flags "--disable apps"''}
    install -Dm755 ${launcher} "$out/bin/codex"
    substituteInPlace "$out/bin/codex" --replace-fail @codex@ "$out/libexec/codex"

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
