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

  viewerIsRemote = pkgs.callPackage ../../pkgs/viewer-is-remote.nix { };

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
      pkgs.coreutils
      viewerIsRemote
    ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}

      for file in "$@"; do
        # Hoisted out of the ssh line: shellcheck reads `basename "$file"`
        # plus `< "$file"` in one command as a read/write conflict (SC2094).
        base="$(basename "$file")"

        if [ -n "$PEER" ] && viewer-is-remote; then
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
