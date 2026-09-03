{
  config,
  lib,
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
      # An incoming viewer mode is authoritative. Otherwise snapshot this
      # machine's applied monitor theme once before the persistent server is
      # created. Unknown state is an error rather than an implicit palette.
      case "$THEME_MODE" in
        dark | light) ;;
        *)
          case "$(${pkgs.coreutils}/bin/readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
            *dark.lua) THEME_MODE=dark ;;
            *light.lua) THEME_MODE=light ;;
            *)
              echo "herdr: cannot determine the applied monitor theme" >&2
              exit 1
              ;;
          esac
          ;;
      esac
      export THEME_MODE
      exec ${pkgs.herdr}/bin/herdr "$@"
      WRAPPER
      chmod +x "$out/bin/herdr"
    '';
  };

  herdrTitle = pkgs.writeShellApplication {
    name = "herdr-title";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../../scripts/herdr-title.py} "$@"
    '';
  };

  # Herdr restores every pane into the directory it was last in, which is not
  # wanted here: after a reboot panes should come up in $HOME. Upstream 0.8.0
  # has no knob for it — `restore()` (src/persist/restore.rs) threads no cwd
  # policy at all, and `[terminal] new_cwd` governs only *newly created* panes
  # (and must stay `follow`, because herdr-agent-launch and herdr-scratch-note
  # rely on inheriting the calling pane's cwd). The restore source is the
  # session snapshot on disk, so the snapshot is the only place to intervene:
  # the script rewrites just the cwd fields and leaves the workspace/tab/pane
  # layout, custom tab names and agent session refs alone.
  herdrResetCwd = pkgs.writeShellApplication {
    name = "herdr-reset-cwd";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 ${../../scripts/herdr-reset-cwd.py} "$@"
    '';
  };

  # Generate the Claude hook through Herdr's own installer so its payload stays
  # aligned with the pinned Herdr package. The matching SessionStart entry is
  # reconciled only into the standard Claude profile in mutable-configs.nix.
  herdrClaudeSessionHook =
    pkgs.runCommand "herdr-claude-session-hook"
      {
        nativeBuildInputs = [ pkgs.herdr ];
      }
      ''
        export HOME="$TMPDIR/home"
        export CLAUDE_CONFIG_DIR="$TMPDIR/claude"
        mkdir -p "$CLAUDE_CONFIG_DIR"
        herdr integration install claude >/dev/null
        install -Dm0555 \
          "$CLAUDE_CONFIG_DIR/hooks/herdr-agent-state.sh" \
          "$out"
      '';

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

      case "''${THEME_MODE:-}" in
        dark | light) ;;
        *)
          echo "remote-herdr-client: THEME_MODE must be supplied by the laptop viewer" >&2
          exit 64
          ;;
      esac
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
    herdrTitle
    herdrResetCwd
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
  xdg.configFile."claude/hooks/herdr-agent-state.sh" = {
    source = herdrClaudeSessionHook;
    executable = true;
  };

  # Runs once per boot, before the first terminal exists and therefore before
  # the Herdr server starts and reads the snapshot. Once per boot is the whole
  # requirement, but `WantedBy` alone does not give it: sd-switch restarts this
  # unit whenever its own definition changes, which would reset a live session's
  # directories mid-activation. The stamp under `%t` is the gate. `%t` is
  # /run/user/$UID, a tmpfs, so a reboot empties it and nothing has to expire or
  # clean up the stamp; every later start this boot fails the condition and is
  # skipped. `ExecStartPost` stamps only on success, so a failed run retries.
  #
  # The script's live-socket probe is now belt-and-braces on this path, but it
  # is still the only guard for a manual `herdr-reset-cwd`, where refusing to
  # rewrite a session that is actually running matters. Named sessions under
  # `sessions/` get the same treatment, since `remote-herdr-client` restores
  # panes exactly the same way.
  systemd.user.services.herdr-reset-cwd = {
    Unit = {
      Description = "Reset Herdr's saved pane directories to the home directory";
      Before = [ "default.target" ];
      ConditionPathExists = "!%t/herdr-reset-cwd.done";
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${herdrResetCwd}/bin/herdr-reset-cwd";
      ExecStartPost = "${pkgs.coreutils}/bin/touch %t/herdr-reset-cwd.done";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      # The snapshot rewrite is temp-file-plus-rename, so the directory itself
      # has to be writable. `-` tolerates a host that has never run Herdr. `%t`
      # is here because ProtectSystem=strict would otherwise leave the runtime
      # directory read-only and the stamp could never be written.
      ReadWritePaths = [
        "-%h/.config/herdr"
        "%t"
      ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      # AF_UNIX only: the sole socket use is probing Herdr's API socket.
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };

    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.herdr-title = {
    Unit = {
      Description = "Mirror agent topics into Herdr tab titles";
    };

    Service = {
      Type = "simple";
      ExecStart = "${herdrTitle}/bin/herdr-title daemon";
      Restart = "on-failure";
      RestartSec = "2s";
      UMask = "0077";
      RuntimeDirectory = "herdr-title";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "herdr-title";
      StateDirectoryMode = "0700";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
    };

    Install.WantedBy = [ "default.target" ];
  };
}
