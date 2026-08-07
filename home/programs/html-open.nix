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

  # Opens a URL on THIS machine's Wayland session. Invoked over SSH, so it
  # inherits no XDG_RUNTIME_DIR or WAYLAND_DISPLAY and has to rediscover the
  # compositor socket itself.
  showUrl = pkgs.writeShellApplication {
    name = "show-url";
    runtimeInputs = [
      pkgs.brave
      pkgs.coreutils
    ];
    text = ''
      url="''${1:-}"
      if [ -z "$url" ]; then
        echo "show-url: usage: show-url URL" >&2
        exit 1
      fi

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
        echo "show-url: no Wayland socket under $XDG_RUNTIME_DIR" >&2
        exit 1
      fi

      # Straight to the browser rather than xdg-open: with no login session
      # around it, the desktop-file lookup chain is fragile. A running brave
      # picks the URL up as a new tab and this returns immediately.
      brave "$url"
    '';
  };

  # Yazi always runs its opener on the machine Yazi itself runs on. Inside a
  # mosh session that means the opener fires on home while the screen is on
  # the laptop, so a plain `brave` would paint a window nobody is sitting in
  # front of. Serve the page over the tailnet and let the peer open it --
  # copying the single file would break the sibling `*_files/` asset trees
  # that R Markdown and Quarto emit next to their output.
  openHtml = pkgs.writeShellApplication {
    name = "open-html";
    runtimeInputs = [
      pkgs.brave
      pkgs.openssh
      pkgs.python3
      pkgs.tailscale
      pkgs.systemd
      pkgs.coreutils
      pkgs.gawk
      viewerIsRemote
    ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}

      # systemd-run --user needs this, and a mosh or SSH shell does not always
      # export it.
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

      # The service manager resolves a bare command name against its own PATH,
      # which has no reason to carry this script's runtime inputs.
      python="$(command -v python3)"

      for file in "$@"; do
        path="$(realpath "$file")"
        dir="$(dirname "$path")"
        base="$(basename "$path")"

        if [ -z "$PEER" ] || ! viewer-is-remote; then
          brave "$path" &
          continue
        fi

        # A literal tailscale IP, never a tailnet hostname: a stale name here
        # resolves into mihomo's fake-IP range (198.18.x) and hangs instead of
        # failing. Binding to it also keeps the tree off every other interface.
        ip="$(tailscale ip -4 | head -n1)"
        if [ -z "$ip" ]; then
          echo "open-html: no tailscale IPv4 address; opening locally" >&2
          brave "$path" &
          continue
        fi

        # One port per directory, so reopening the same tree reuses its server
        # instead of piling up. The hash is narrow enough that two trees can
        # collide on a port, hence the working-directory check below.
        port=$(( 8700 + $(printf '%s' "$dir" | cksum | awk '{ print $1 % 100 }') ))
        unit="html-open-$port.service"

        if [ "$(systemctl --user show -p WorkingDirectory --value "$unit" 2>/dev/null)" != "$dir" ] \
          || ! systemctl --user is-active --quiet "$unit"; then
          systemctl --user stop "$unit" 2>/dev/null || true
          # Rooted at the file's own directory, never $HOME or /: the port is
          # unauthenticated on the tailnet for as long as it lives, so expose
          # the page's own assets and nothing else, and cap the lifetime.
          systemd-run --user --collect --quiet "--unit=$unit" \
            --working-directory="$dir" \
            --property=RuntimeMaxSec=3600 \
            "$python" -m http.server --bind "$ip" "$port"
        fi

        # Basenames carry spaces and other characters that are not URL-safe.
        enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$base")"

        # accept-new rather than a pinned key: the peer's identity is already
        # enforced by the tailnet, and a first push should not fail just
        # because known_hosts has no entry yet.
        if ssh -o BatchMode=yes -o ConnectTimeout=5 \
            -o StrictHostKeyChecking=accept-new "$PEER" \
            ${profileBin}/show-url "http://$ip:$port/$enc"; then
          continue
        fi
        echo "open-html: push to $PEER failed; opening locally" >&2
        brave "$path" &
      done
    '';
  };
in
{
  home.packages = [
    showUrl
    openHtml
  ];
}
