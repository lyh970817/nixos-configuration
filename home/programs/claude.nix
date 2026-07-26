{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  claudeHostEnvironment = ''
    export TZ="Europe/London"
    export TZDIR="${pkgs.tzdata}/share/zoneinfo"

    export LANG="en_GB.UTF-8"
    export LC_ALL="en_GB.UTF-8"
    export LANGUAGE="en_GB:en"
    export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"

    export HTTP_PROXY="''${HTTP_PROXY:-http://127.0.0.1:7890}"
    export HTTPS_PROXY="''${HTTPS_PROXY:-http://127.0.0.1:7890}"
    export ALL_PROXY="''${ALL_PROXY:-socks5h://127.0.0.1:7890}"
    export NO_PROXY="''${NO_PROXY:-localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"

    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export all_proxy="$ALL_PROXY"
    export no_proxy="$NO_PROXY"

    export DISABLE_TELEMETRY="1"
    export DISABLE_ERROR_REPORTING="1"
    export ENABLE_EXPERIMENTAL_MCP_CLI="true"
    # Force full alt-screen repaints to stop residual flicker/jumping on the
    # fullscreen renderer (terminal coalesces positioned writes otherwise).
    export CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT="1"
    export MCP_TIMEOUT="60000"
  '';

  claudeHostLauncher = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"

      ${claudeHostEnvironment}

      # Claude Code has no --theme flag or CLAUDE_THEME/CLAUDE_CODE_THEME env
      # var. --settings lands in flagSettings, which outranks userSettings
      # (settings.json) and is never written back to disk, so this can't
      # fight the activation-time settings.json writer.
      theme_mode="''${THEME_MODE:-dark}"
      case "$theme_mode" in
        dark | light) ;;
        *) theme_mode="dark" ;;
      esac

      exec ${pkgs.claude-code}/bin/claude --settings "{\"theme\":\"''${theme_mode}-ansi\"}" "$@"
    '';
  };

  claudeGpt56Launcher = pkgs.writeShellApplication {
    name = "claude-gpt56";
    text = ''
      export CLAUDE_CONFIG_DIR="$HOME/.config/claude-gpt56"

      ${claudeHostEnvironment}

      case "''${1:-}" in
        --help | -h | --version | -v)
          exec ${pkgs.claude-code}/bin/claude "$@"
          ;;
      esac

      state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
      data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
      client_key_file="$state_home/cli-proxy-api/client-key"
      if [ ! -s "$client_key_file" ]; then
        echo "CLIProxyAPI client key is missing; run cli-proxy-api-codex-login first." >&2
        exit 1
      fi
      shopt -s nullglob
      codex_auth=("$data_home"/cli-proxy-api/auth/codex-*.json)
      shopt -u nullglob
      if [ "''${#codex_auth[@]}" -eq 0 ]; then
        echo "CLIProxyAPI Codex OAuth credentials are missing; run cli-proxy-api-codex-login first." >&2
        exit 1
      fi

      ${pkgs.systemd}/bin/systemctl --user start cli-proxy-api.service

      client_key="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$client_key_file")"
      gateway_ready=0
      for _ in {1..12}; do
        if printf 'header = "Authorization: Bearer %s"\n' "$client_key" \
          | ${pkgs.curl}/bin/curl \
            --config - \
            --silent \
            --show-error \
            --fail \
            --connect-timeout 0.2 \
            --max-time 0.5 \
            --output /dev/null \
            "http://127.0.0.1:8317/v1/models" 2>/dev/null; then
          gateway_ready=1
          break
        fi
        ${pkgs.coreutils}/bin/sleep 0.25
      done
      if [ "$gateway_ready" -ne 1 ]; then
        echo "CLIProxyAPI did not become ready on 127.0.0.1:8317; inspect cli-proxy-api.service." >&2
        exit 1
      fi

      export ANTHROPIC_BASE_URL="http://127.0.0.1:8317"
      export ANTHROPIC_AUTH_TOKEN="$client_key"
      unset client_key
      unset ANTHROPIC_API_KEY

      # Keep Claude Code's native semantic model slots, but terminate every
      # route at the local GPT-5.6 gateway. Built-in Agent calls commonly use
      # these slot names when selecting a cheaper or stronger subagent.
      export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-gpt-5-6-sol"
      export ANTHROPIC_DEFAULT_OPUS_MODEL_NAME="GPT 5.6 Sol"
      export ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES="effort,xhigh_effort,max_effort"
      export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-gpt-5-6-terra"
      export ANTHROPIC_DEFAULT_SONNET_MODEL_NAME="GPT 5.6 Terra"
      export ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES="effort,xhigh_effort,max_effort"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-gpt-5-6-luna"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME="GPT 5.6 Luna"
      export ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES="effort,xhigh_effort,max_effort"

      unset CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY
      unset CLAUDE_CODE_SUBAGENT_MODEL

      # Claude Code has no --theme flag or CLAUDE_THEME/CLAUDE_CODE_THEME env
      # var. --settings lands in flagSettings, which outranks userSettings
      # (settings.json) and is never written back to disk, so this can't
      # fight the activation-time settings.json writer.
      theme_mode="''${THEME_MODE:-dark}"
      case "$theme_mode" in
        dark | light) ;;
        *) theme_mode="dark" ;;
      esac

      exec ${pkgs.claude-code}/bin/claude --settings "{\"theme\":\"''${theme_mode}-ansi\"}" "$@"
    '';
  };

in
{
  # Coding CLI: installed on both home and remote roles.
  config = {
    home.packages = [
      claudeHostLauncher
      claudeGpt56Launcher
    ];

    home.sessionVariables.CLAUDE_CONFIG_DIR = "$HOME/.config/claude";

    # Commands, agents, and runtime profile state stay mutable under each
    # CLAUDE_CONFIG_DIR. settings.json is materialized from a tracked
    # non-secret baseline, then the theme hooks keep every profile's theme live.
  };
}
