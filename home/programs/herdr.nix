{
  config,
  osConfig,
  pkgs,
  ...
}:

let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";

  # Herdr keeps a persistent server behind its short-lived clients. Resolve the
  # mode before that server starts so it is inherited by the server and every
  # pane it later creates, rather than letting a later desktop switch retheme an
  # already-running session.
  herdrWrapped = pkgs.symlinkJoin {
    name = "herdr-wrapped";
    paths = [ pkgs.herdr ];
    postBuild = ''
      rm "$out/bin/herdr"
      cat > "$out/bin/herdr" <<'WRAPPER'
      #!/usr/bin/env bash
      # An incoming session mode is authoritative. Otherwise snapshot this
      # machine's desktop mode once, using the same dark-versus-light fallback
      # as theme-mode and btop.
      case "$THEME_MODE" in
        dark | light) ;;
        *)
          case "$(readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
            *dark.lua) THEME_MODE=dark ;;
            *) THEME_MODE=light ;;
          esac
          ;;
      esac
      export THEME_MODE
      exec ${pkgs.herdr}/bin/herdr "$@"
      WRAPPER
      chmod +x "$out/bin/herdr"
    '';
  };
in
{
  # Terminal agent multiplexer; useful on both roles, so it is not gated on
  # `portable.role`. The package comes from the pinned upstream flake input
  # via the overlay in flake.nix.
  home.packages = [ herdrWrapped ];

  # herdr rewrites its own config.toml at runtime: `mark_onboarding_complete`
  # clears the first-run wizard and the in-app Settings screen saves through the
  # same path. A read-only /nix/store copy makes the wizard reappear on every
  # launch and makes Settings fail silently, so the authored config is an
  # out-of-store symlink into this repo — writes go through to
  # dotfiles/herdr/config.toml and stay in version control. Safe because the
  # writer is a plain in-place `fs::write` (src/app/config_io.rs), not
  # temp-file+rename, so it follows the link instead of replacing it.
  #
  # Only config.toml is linked, never the whole directory: herdr resolves its
  # data dir from `config_dir()` independently of the config file's location and
  # drops herdr.log, herdr-client.log, herdr-server.log, plugins.json,
  # session.json and its sockets in there. Home Manager materializes
  # ~/.config/herdr as a real directory when only a nested path is managed, so
  # that runtime state stays writable and out of the repo.
  #
  # See dotfiles/herdr/config.toml for the layout and theme rationale.
  xdg.configFile."herdr/config.toml".source = link "dotfiles/herdr/config.toml";
}
