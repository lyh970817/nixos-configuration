{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  peerHost = osConfig.portable.peerHost;

  # Stable across generations, unlike a /nix/store path. The dispatcher below
  # invokes this over SSH, where a non-interactive shell may not have the
  # Home Manager profile on PATH, so it needs a fixed absolute location.
  profileBin = "/etc/profiles/per-user/${config.home.username}/bin";

  # Receives image bytes on stdin and shows them on THIS machine's Wayland
  # session. Invoked over SSH, so it inherits no XDG_RUNTIME_DIR or
  # WAYLAND_DISPLAY and has to rediscover the compositor socket itself.
  showImage = pkgs.writeShellApplication {
    name = "show-image";
    runtimeInputs = [
      pkgs.imv
      pkgs.coreutils
    ];
    text = ''
      name="''${1:-image}"

      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

      if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
          case "$sock" in
            *.lock) continue ;;
          esac
          [ -S "$sock" ] || continue
          WAYLAND_DISPLAY="$(basename "$sock")"
          export WAYLAND_DISPLAY
          break
        done
      fi

      if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        echo "show-image: no Wayland socket under $XDG_RUNTIME_DIR" >&2
        exit 1
      fi

      dir="$(mktemp -d /tmp/show-image.XXXXXXXX)"
      trap 'rm -rf "$dir"' EXIT
      file="$dir/$(basename "$name")"
      cat > "$file"

      imv "$file"
    '';
  };

  # Yazi always runs its opener on the machine Yazi itself runs on. Inside a
  # mosh session that means the opener fires on home while the screen is on
  # the laptop, so a plain `imv` would paint a window nobody is sitting in
  # front of. Detect that case and ship the bytes to the peer instead.
  openImage = pkgs.writeShellApplication {
    name = "yazi-open-image";
    runtimeInputs = [
      pkgs.imv
      pkgs.openssh
      pkgs.tmux
      pkgs.procps
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}

      # True when a tmux client attached to this session descends from
      # mosh-server -- i.e. the human is at the far end of a mosh link.
      # Control-mode clients (editor and agent integrations) are skipped:
      # nobody is looking at those.
      viewer_is_remote() {
        [ -n "''${TMUX:-}" ] || return 1

        local session pid comm
        session="$(tmux display-message -p '#{session_name}' 2>/dev/null)" || return 1

        while read -r pid; do
          while [ -n "$pid" ]; do
            case "$pid" in
              *[!0-9]*) break ;;
            esac
            [ "$pid" -gt 1 ] || break
            comm="$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
            if [ "$comm" = "mosh-server" ]; then
              return 0
            fi
            pid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
          done
        done < <(
          tmux list-clients -t "$session" \
            -F '#{client_control_mode} #{client_pid}' 2>/dev/null \
            | awk '$1 == 0 { print $2 }'
        )

        return 1
      }

      for file in "$@"; do
        # Hoisted out of the ssh line: shellcheck reads `basename "$file"`
        # plus `< "$file"` in one command as a read/write conflict (SC2094).
        base="$(basename "$file")"

        if [ -n "$PEER" ] && viewer_is_remote; then
          # accept-new rather than a pinned key: the peer's identity is already
          # enforced by the tailnet, and a first push should not fail just
          # because known_hosts has no entry yet.
          if ssh -o BatchMode=yes -o ConnectTimeout=5 \
              -o StrictHostKeyChecking=accept-new "$PEER" \
              ${profileBin}/show-image "$base" < "$file"; then
            continue
          fi
          echo "yazi-open-image: push to $PEER failed; opening locally" >&2
        fi
        imv "$file" &
      done
    '';
  };
in
{
  home.packages = [
    showImage
    openImage
  ];
}
