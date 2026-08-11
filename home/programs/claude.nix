{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  claudeEnvironment = ../../dotfiles/claude/environment.json;

  claudeHostEnvironment = ''
    export TZ="Europe/London"
    export TZDIR="${pkgs.tzdata}/share/zoneinfo"

    export LANG="en_GB.UTF-8"
    export LC_ALL="en_GB.UTF-8"
    export LANGUAGE="en_GB:en"
    export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"

    claude_environment=${lib.escapeShellArg (toString claudeEnvironment)}
    claude_env_value() {
      ${pkgs.jq}/bin/jq -r --arg key "$1" '.[$key] // empty' "$claude_environment"
    }
    export ALL_PROXY="''${ALL_PROXY:-$(claude_env_value ALL_PROXY)}"
    export DISABLE_ERROR_REPORTING="''${DISABLE_ERROR_REPORTING:-$(claude_env_value DISABLE_ERROR_REPORTING)}"
    export DISABLE_TELEMETRY="''${DISABLE_TELEMETRY:-$(claude_env_value DISABLE_TELEMETRY)}"
    export HTTPS_PROXY="''${HTTPS_PROXY:-$(claude_env_value HTTPS_PROXY)}"
    export HTTP_PROXY="''${HTTP_PROXY:-$(claude_env_value HTTP_PROXY)}"
    export MCP_TIMEOUT="''${MCP_TIMEOUT:-$(claude_env_value MCP_TIMEOUT)}"
    export NO_PROXY="''${NO_PROXY:-$(claude_env_value NO_PROXY)}"
    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export all_proxy="$ALL_PROXY"
    export no_proxy="$NO_PROXY"

    # Launcher-only process wiring; these values are intentionally not persisted
    # in settings.json or environment.json.
    export CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT="1"
    export CLAUDE_CODE_PROCESS_WRAPPER="${claudeProcessWrapper}/bin/claude-process-wrapper"
  '';

  claudeThemeSettings = ''
    # Claude Code has no --theme flag or CLAUDE_THEME/CLAUDE_CODE_THEME env
    # var. --settings lands in flagSettings, which outranks userSettings
    # (settings.json) and is never written back to disk, so this can't
    # fight the activation-time settings.json writer.
    theme_mode="''${THEME_MODE:-dark}"
    case "$theme_mode" in
      dark | light) ;;
      *) theme_mode="dark" ;;
    esac

    # Dark mode names the custom theme installed by programs/mutable-configs.nix
    # rather than dark-ansi itself: it is dark-ansi with the three slab
    # backgrounds moved off ANSI bright black, which is what lets bright black
    # carry a readable rung for diff comments. A slug that fails to resolve
    # falls back to the 24-bit "dark" theme silently, so this string has to
    # match the theme file name there. Light mode needs no such indirection.
    case "$theme_mode" in
      dark) claude_theme="custom:phosphor-dark" ;;
      *) claude_theme="light-ansi" ;;
    esac

    # The spinner's effort suffix ("thinking with high effort") is drawn in a
    # hardcoded RGB grey that pulses between #999999 and #B9B9B9. It is not a
    # theme key, so no ANSI theme can reach it and it lands as raw grey in the
    # amber palette. Reduced motion selects the spinner branch that colours
    # that text from the theme instead. It also stills the spinner glyph and
    # drops the shimmer, which suits the operator console anyway.
    claude_flag_settings="{\"theme\":\"$claude_theme\",\"prefersReducedMotion\":true}"
  '';

  # Claude Code uses this supported launcher prefix for its own re-execs and
  # background processes. Its argv contract is the real target followed by
  # that target's arguments, so execute the target directly: invoking either
  # user-facing launcher here would wrap the wrapper recursively. Keep the
  # process-wrapper variable inherited so every descendant Claude process uses
  # the same path for any later self-exec.
  claudeProcessWrapper = pkgs.writeShellApplication {
    name = "claude-process-wrapper";
    text = ''
      if [ "$#" -eq 0 ]; then
        echo "claude-process-wrapper: missing target" >&2
        exit 64
      fi

      claude_target="$1"
      shift

      ${claudeThemeSettings}
      exec "$claude_target" --settings "$claude_flag_settings" "$@"
    '';
  };

  claudeHostLauncher = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"

      ${claudeHostEnvironment}

      ${claudeThemeSettings}
      exec ${pkgs.claude-code}/bin/claude --settings "$claude_flag_settings" "$@"
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

      ${claudeThemeSettings}
      exec ${pkgs.claude-code}/bin/claude --settings "$claude_flag_settings" "$@"
    '';
  };

in
{
  # Coding CLI: installed on both home and remote roles.
  config = {
    home.packages = [
      claudeHostLauncher
      claudeGpt56Launcher
      # Standalone Claude Science workbench binary, not a Claude Code plugin; no wrapper needed.
      pkgs.claude-science
    ];

    home.sessionVariables.CLAUDE_CONFIG_DIR = "$HOME/.config/claude";

    # Commands, agents, and runtime profile state stay mutable under each
    # CLAUDE_CONFIG_DIR. settings.json is reconciled from tracked policy
    # fields by activation. The session theme is launcher-owned -- both the
    # initial command and Claude's supported process wrapper pass flagSettings,
    # which outranks settings.json. Activation also writes a machine-mode theme
    # there as a fallback for a truly direct, unwrapped binary launch.
  };
}
