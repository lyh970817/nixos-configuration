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
      #!${pkgs.runtimeShell}
      # An incoming session mode is authoritative. Otherwise snapshot this
      # machine's desktop mode once, using the same dark-versus-light fallback
      # as theme-mode and btop.
      case "$THEME_MODE" in
        dark | light) ;;
        *)
          case "$(${pkgs.coreutils}/bin/readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
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

  # A remote client is the only attachment that means the human is viewing the
  # home session from the laptop. Its per-client lease distinguishes that case
  # from a local attachment to the same named session. `exec` leaves a stale
  # lease after a client exits; viewers validate PID and starttime and ignore it.
  remoteHerdrClient = pkgs.writeShellApplication {
    name = "remote-herdr-client";
    runtimeInputs = [
      herdrWrapped
      pkgs.coreutils
    ];
    text = ''
      set -eu

      uid="$(id -u)"
      runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
      if [ ! -d "$runtime_dir" ] || [ -L "$runtime_dir" ] \
        || [ "$(stat -c '%u:%a' "$runtime_dir")" != "$uid:700" ]; then
        echo "remote-herdr-client: refusing untrusted runtime directory: $runtime_dir" >&2
        exit 1
      fi

      lease_dir="$runtime_dir/herdr-remote-view"
      if [ -L "$lease_dir" ]; then
        echo "remote-herdr-client: refusing symbolic-link lease directory: $lease_dir" >&2
        exit 1
      fi
      umask 077
      if [ ! -e "$lease_dir" ]; then
        mkdir --mode=700 -- "$lease_dir" 2>/dev/null || true
      fi
      if [ ! -d "$lease_dir" ] || [ -L "$lease_dir" ] \
        || [ "$(stat -c '%u:%a' "$lease_dir")" != "$uid:700" ]; then
        echo "remote-herdr-client: refusing unsafe lease directory: $lease_dir" >&2
        exit 1
      fi

      proc_starttime() {
        local proc_stat proc_fields
        proc_stat="$(<"/proc/$1/stat")" || return 1
        proc_fields="''${proc_stat##*) }"
        # shellcheck disable=SC2086 # split the post-comm stat fields by design
        set -- $proc_fields
        printf '%s\n' "''${20:-}"
      }
      starttime="$(proc_starttime "$$")"
      case "$starttime" in
        "" | *[!0-9]*)
          echo "remote-herdr-client: could not read process start time" >&2
          exit 1
          ;;
      esac
      lease="$lease_dir/$$-$starttime"
      temporary_lease="$(mktemp "$lease_dir/.remote-herdr-lease.XXXXXX")"
      if [ ! -f "$temporary_lease" ] || [ -L "$temporary_lease" ] \
        || [ "$(stat -c '%u:%a' "$temporary_lease")" != "$uid:600" ]; then
        echo "remote-herdr-client: refusing unsafe temporary lease: $temporary_lease" >&2
        exit 1
      fi
      printf 'pid=%s\nstarttime=%s\n' "$$" "$starttime" > "$temporary_lease"
      if ! ln -T -- "$temporary_lease" "$lease"; then
        rm -f -- "$temporary_lease"
        echo "remote-herdr-client: could not reserve lease: $lease" >&2
        exit 1
      fi
      rm -f -- "$temporary_lease"
      if [ ! -f "$lease" ] || [ -L "$lease" ] \
        || [ "$(stat -c '%u:%a' "$lease")" != "$uid:600" ]; then
        echo "remote-herdr-client: refusing unsafe lease file: $lease" >&2
        exit 1
      fi

      export THEME_MODE=dark
      exec herdr --session remote "$@"
    '';
  };
in
{
  # Terminal agent multiplexer; useful on both roles, so it is not gated on
  # `portable.role`. The package comes from the pinned upstream flake input
  # via the overlay in flake.nix.
  home.packages = [
    herdrWrapped
    remoteHerdrClient
  ];

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
