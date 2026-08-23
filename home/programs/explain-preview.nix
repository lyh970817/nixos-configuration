{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  peerHost = osConfig.portable.peerHost;

  # Stable across generations; see html-open.nix for why the SSH dispatch needs
  # a fixed absolute location for the peer-side helper.
  profileBin = "/etc/profiles/per-user/${config.home.username}/bin";

  viewerIsRemote = pkgs.callPackage ../../pkgs/viewer-is-remote.nix { };

  # live-preview.nvim serves the explanation tree from inside Neovim (KaTeX,
  # scroll sync, websocket updates). The nixpkgs pin wedges the editor on
  # start; see the patch header. dotfiles/nvim/lua/plugins/explain-preview.lua
  # loads this store path via lazy's `dir`, same mechanism as the vendored
  # render-markdown.nvim in dotfiles.nix.
  livePreview = pkgs.applyPatches {
    name = "live-preview.nvim-no-uv-run";
    src = pkgs.vimPlugins.live-preview-nvim;
    patches = [ ./live-preview-remove-uv-run.patch ];
  };

  # Network decisions and browser dispatch for the explanation preview, kept
  # out of the Lua config so the Neovim side stays host-agnostic. `info`
  # answers "where should the in-editor server bind"; `open` puts a tab in
  # front of the human, wherever they are looking (same dispatch as
  # html-open.nix). The port is unauthenticated on the tailnet for the life of
  # the Neovim instance -- the served tree is narrowed to one explanation root
  # (dynamic_root in the Lua config), the same deliberately accepted trust
  # model as html-open's http.server.
  explainPreview = pkgs.writeShellApplication {
    name = "explain-preview";
    runtimeInputs = [
      pkgs.brave
      pkgs.openssh
      pkgs.tailscale
      pkgs.coreutils
      pkgs.gawk
      viewerIsRemote
    ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}

      case "''${1:-}" in
        info)
          # A literal tailscale IP, never a tailnet hostname: a stale name
          # resolves into mihomo's fake-IP range and hangs (see html-open.nix).
          # Binding to it also keeps the tree off every other interface. The
          # same IP works from the laptop and from this machine itself; with
          # no tailscale the preview degrades to loopback-only.
          ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
          [ -n "$ip" ] || ip=127.0.0.1

          # Deterministic port, mirroring html-open's 8700+cksum scheme in a
          # band of its own so the two ranges cannot collide. One port for the
          # whole workflow: a Neovim instance runs at most one preview server,
          # and the explain workflow runs in one dedicated Neovim.
          port=$(( 8800 + $(printf '%s' explain-preview | cksum | awk '{ print $1 % 100 }') ))

          printf '%s %s\n' "$ip" "$port"
          ;;
        open)
          url="''${2:-}"
          if [ -z "$url" ]; then
            echo "explain-preview: usage: explain-preview open URL" >&2
            exit 1
          fi

          # accept-new rather than a pinned key: the peer's identity is
          # already enforced by the tailnet (see html-open.nix).
          if [ -n "$PEER" ] && viewer-is-remote; then
            if ssh -o BatchMode=yes -o ConnectTimeout=5 \
                -o StrictHostKeyChecking=accept-new "$PEER" \
                ${profileBin}/show-url "$url"; then
              exit 0
            fi
            echo "explain-preview: push to $PEER failed; opening locally" >&2
          fi
          brave "$url" &
          ;;
        *)
          echo "explain-preview: usage: explain-preview info | open URL" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  home.packages = [ explainPreview ];

  # Patched live-preview.nvim source for the lazy `dir` spec in
  # dotfiles/nvim/lua/plugins/explain-preview.lua; see livePreview above.
  xdg.configFile."nvim/vendor/live-preview.nvim".source = livePreview;
}
