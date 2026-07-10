{ pkgs, ... }:

let
  codexCli = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      user_codex="''${CODEX_USER_CLI_PATH:-$HOME/.npm-global/bin/codex}"
      if [ -x "$user_codex" ]; then
        if [ "''${1:-}" = "app-server" ]; then
          desktop_exe="$(readlink -f "/proc/$PPID/exe")"
          desktop_root="''${desktop_exe%%/opt/codex-desktop/*}/opt/codex-desktop"
          exec "$user_codex" "$@" \
            -c 'plugins."browser@openai-bundled".enabled=true' \
            -c 'mcp_servers.node_repl={ args=[], command="'"$desktop_root"'/resources/node_repl", enabled=true, startup_timeout_sec=120, env={ NODE_REPL_NATIVE_PIPE_CONNECT_TIMEOUT_MS="1000", NODE_REPL_NODE_MODULE_DIRS="", NODE_REPL_NODE_PATH="'"$desktop_root"'/resources/node-runtime/bin/node", NODE_REPL_TRUSTED_CODE_PATHS="'"$HOME"'/.codex", CODEX_HOME="'"$HOME"'/.codex", NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S="60e4902788f207f88fd09344dfeafe07769488bdb2924bbb12b322c3b9d2b999", BROWSER_USE_AVAILABLE_BACKENDS="chrome,iab", NODE_REPL_INSTRUCTIONS_USE_CASE_BROWSER="Control the in-app browser in conjunction with the Browser Plugin.", NODE_REPL_INSTRUCTIONS_USE_CASE_CHROME="Control the Chrome browser in conjunction with the Chrome Plugin. Prefer this method of controlling Chrome over alternatives (such as Computer Use) unless the user explicitly mentions an alternative.", BROWSER_USE_CODEX_APP_BUILD_FLAVOR="prod", BROWSER_USE_CODEX_APP_VERSION="26.623.101652" }, tools={ js={ approval_mode="approve" } } }'
        fi

        exec "$user_codex" "$@"
      fi

      echo "Codex CLI not found at $user_codex" >&2
      exit 127
    '';
  };
in
{
  programs.codexDesktopLinux = {
    enable = true;
    cliPackage = codexCli;
  };
}
