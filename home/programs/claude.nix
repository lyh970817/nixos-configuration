{
  pkgs,
  lib,
  config,
  ...
}:

let
  claudeContainerLauncher = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [
      pkgs.coreutils
    ];
    text = ''
      container="claude-uk"
      nixos_container="/run/current-system/sw/bin/nixos-container"
      sudo="/run/wrappers/bin/sudo"

      if [ ! -x "$nixos_container" ]; then
        echo "nixos-container is not installed yet; run nixos-rebuild switch first." >&2
        exit 127
      fi

      workdir="$(pwd -P)"
      env_dir="$HOME/.cache/claude-container"
      env_file="$env_dir/env.$$"
      cleanup() {
        rm -f "$env_file"
        if [ -n "''${mount_dir:-}" ]; then
          if /run/current-system/sw/bin/mountpoint -q "$mount_dir"; then
            "$sudo" /run/current-system/sw/bin/umount -R "$mount_dir" \
              || "$sudo" /run/current-system/sw/bin/umount -l "$mount_dir" \
              || true
          fi
          rmdir "$mount_dir" 2>/dev/null || true
        fi
      }
      trap cleanup EXIT
      trap 'cleanup; exit 130' INT TERM

      mkdir -p "$env_dir"
      umask 077
      : > "$env_file"

      case "$workdir" in
        /home/andongni|/home/andongni/*)
          container_workdir="$workdir"
          ;;
        /*)
          mount_dir="$HOME/.cache/claude-container/work.$$"
          mkdir -p "$mount_dir"
          "$sudo" /run/current-system/sw/bin/mount --bind "$workdir" "$mount_dir"
          "$sudo" /run/current-system/sw/bin/mount --make-private "$mount_dir"
          container_workdir="$mount_dir"
          ;;
        *)
          echo "claude container requires an absolute working directory." >&2
          exit 66
          ;;
      esac

      forward_env() {
        local name="$1"
        if [ -n "''${!name+x}" ]; then
          printf '%s=%s\0' "$name" "''${!name}" >> "$env_file"
        fi
      }

      for name in \
        ANTHROPIC_AUTH_TOKEN \
        ANTHROPIC_BASE_URL \
        ANTHROPIC_DEFAULT_HAIKU_MODEL \
        ANTHROPIC_DEFAULT_OPUS_MODEL \
        ANTHROPIC_DEFAULT_SONNET_MODEL \
        CLAUDE_CODE_SUBAGENT_MODEL \
        CLAUDE_CONFIG_DIR \
        GITHUB_TOKEN \
        GH_TOKEN \
        GIT_ASKPASS \
        NIX_CONFIG \
        SSH_AUTH_SOCK \
        VISUAL \
        EDITOR
      do
        forward_env "$name"
      done

      "$sudo" "$nixos_container" start "$container" >/dev/null
      "$sudo" "$nixos_container" run "$container" -- \
        /run/current-system/sw/bin/claude-container-entry \
        "$container_workdir" \
        "''${TERM:-xterm-256color}" \
        "''${COLORTERM:-}" \
        "$env_file" \
        "$@"
      status="$?"
      trap - EXIT
      cleanup
      exit "$status"
    '';
  };

  settings = {
    env = {
      # ANTHROPIC_AUTH_TOKEN = "test";
      # ANTHROPIC_BASE_URL = "http://localhost:8080";
      # _ANTHROPIC_MODEL = "gemini-3-pro-high[1m]";
      # ANTHROPIC_DEFAULT_OPUS_MODEL = "claude-opus-4-5-thinking";
      # ANTHROPIC_DEFAULT_SONNET_MODEL = "claude-sonnet-4-5-thinking";
      # ANTHROPIC_DEFAULT_HAIKU_MODEL = "claude-sonnet-4-5";
      # CLAUDE_CODE_SUBAGENT_MODEL = "claude-sonnet-4-5-thinking";
      ENABLE_EXPERIMENTAL_MCP_CLI = "true";
      DISABLE_TELEMETRY = "1";
      DISABLE_ERROR_REPORTING = "1";
      HTTP_PROXY = "http://127.0.0.1:7890";
      HTTPS_PROXY = "http://127.0.0.1:7890";
      ALL_PROXY = "socks5://127.0.0.1:7890";
      NO_PROXY = "localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12";
      # CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
      MCP_TIMEOUT = "60000";
      CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    };
    includeCoAuthoredBy = false;
    permissions = {
      allow = [
        "Bash"
        "BashOutput"
        "Edit"
        "Glob"
        "Grep"
        "KillShell"
        "NotebookEdit"
        "Read"
        "SlashCommand"
        "Task"
        "TodoWrite"
        "WebFetch"
        "WebSearch"
        "Write"
      ];
      deny = [ ];
    };
    model = "opus";
    statusLine = {
      type = "command";
      command = "~/.claude/statusline.sh";
    };
  };

in
{
  home.packages = [
    claudeContainerLauncher
  ];

  home.file.".claude/settings.json".text = builtins.toJSON settings;

  home.file.".claude/statusline.sh" = {
    source = ../../dotfiles/claude/statusline.sh;
    executable = true;
  };

  # Note: Custom commands and agents in .claude/commands/zcf and .claude/agents/zcf
  # are currently left as manually managed or can be migrated to this file using recursive file linking
  # if we move the source files into the nixos repo.
}
