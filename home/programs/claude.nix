{ pkgs, ... }:

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
      export CLAUDE_CONFIG_DIR="''${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}"
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

      mkdir -p "$env_dir" "$CLAUDE_CONFIG_DIR"
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

in
{
  home.packages = [
    claudeContainerLauncher
  ];

  home.sessionVariables.CLAUDE_CONFIG_DIR = "$HOME/.config/claude";

  # Claude settings, commands, agents, and themes are intentionally mutable under
  # ~/.config/claude via CLAUDE_CONFIG_DIR.
}
