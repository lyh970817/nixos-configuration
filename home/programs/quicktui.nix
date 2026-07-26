{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  homeDir = config.home.homeDirectory;

  # Access token source in the config repo's git-ignored secrets/ dir
  # (portable.configDir, shared with the system via osConfig). Referenced as a
  # plain string so the token never reaches the world-readable store and
  # evaluation still succeeds while the file is absent. The file holds the raw
  # token on a single line.
  tokenSourcePath = "${osConfig.portable.configDir}/secrets/quicktui-token";

  # Config *and* device-pairing/E2E identity state share one directory, so it
  # has to survive reboots: $XDG_RUNTIME_DIR is tmpfs and would silently
  # un-pair every phone on each boot. The server also refuses to start unless
  # this directory is exactly 0700 ("deviceauth: state directory permissions
  # must be 0700").
  stateDir = "${homeDir}/.local/share/quicktui";
  configPath = "${stateDir}/config";
  tokenRuntimePath = "${stateDir}/token";

  # Bind every interface rather than the tailnet address. modules/system/
  # networking.nix runs a default-deny firewall that does not list 8022 in
  # allowedTCPPorts and does trust tailscale0, so the socket is reachable only
  # over the tailnet and loopback. Naming the tailnet IP instead would hardcode
  # a machine-specific address and make the unit fail to start whenever
  # tailscaled has not finished bringing the interface up.
  listenAddr = "0.0.0.0:8022";

  # quicktui compares the requested locale against `locale -a` verbatim, and
  # that listing carries the normalised "en_GB.utf8" spelling of the
  # i18n.defaultLocale set in modules/system/locale.nix. Passing "en_GB.UTF-8"
  # makes it warn and silently fall back to C.UTF-8.
  lang = "en_GB.utf8";
  term = "xterm-256color";

  # The server rewrites its own config file (it persists QUICKTUI_TMUX_SOCKET on
  # first start) and takes the token only from that file or from --token, so the
  # config cannot be a read-only store symlink (no home.file) and the token
  # cannot be passed on the command line. Despite what --help claims,
  # QUICKTUI_TOKEN in the environment is ignored. Re-rendering the file on every
  # start is safe: pairing state lives in separate files in the same directory,
  # not in `config`. Plain KEY=VALUE lines, not JSON.
  renderConfig = pkgs.writeShellApplication {
    name = "quicktui-render-config";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      umask 077

      uid="$(id -u)"
      runtime_home="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
      state_dir=${lib.escapeShellArg stateDir}
      config_file=${lib.escapeShellArg configPath}

      mkdir -p "$state_dir"
      chmod 0700 "$state_dir"

      token="$(tr -d '\r\n' < ${lib.escapeShellArg tokenRuntimePath})"
      if [ -z "$token" ]; then
        echo "quicktui: ${tokenSourcePath} is empty" >&2
        exit 1
      fi

      config_tmp="$(mktemp "$state_dir/config.XXXXXX")"
      {
        printf 'QUICKTUI_TOKEN=%s\n' "$token"
        printf 'QUICKTUI_ADDR=%s\n' ${lib.escapeShellArg listenAddr}
        printf 'QUICKTUI_TERM=%s\n' ${lib.escapeShellArg term}
        printf 'QUICKTUI_LANG=%s\n' ${lib.escapeShellArg lang}
        # home/programs/tmux.nix leaves home-manager's secureSocket enabled, so
        # interactive sessions live under $XDG_RUNTIME_DIR, not the /tmp path
        # quicktui would default to inside a systemd unit.
        printf 'QUICKTUI_TMUX_SOCKET=%s\n' "$runtime_home/tmux-$uid/default"
      } > "$config_tmp"

      chmod 0600 "$config_tmp"
      mv -f "$config_tmp" "$config_file"
    '';
  };
in
{
  # Remote terminal access to this machine's tmux sessions. Home role only: the
  # QuickTUI free tier covers a single server, so the portable laptop is left
  # out until a Pro licence is in place.
  #
  # The binary is managed by Nix: never use its self-management flags
  # (--upgrade-server, --check-upgrade, --install-service, --uninstall-service,
  # --restart-service). They would write to the read-only store path or install
  # a systemd unit competing with the one below; bump pkgs/quicktui.nix instead.
  config = lib.mkIf (osConfig.portable.role == "home") {
    home.packages = [ pkgs.quicktui ];

    # Copy the user-owned token into quicktui's state directory at activation. A
    # missing source is tolerated so activation never fails without the secret.
    # The directory is created 0700 here too (not just in the render script) so
    # an existing looser directory is corrected before the unit starts.
    home.activation.quicktuiToken = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
      if [ -e ${lib.escapeShellArg tokenSourcePath} ]; then
        run ${pkgs.coreutils}/bin/install -d -m700 $VERBOSE_ARG -- \
          ${lib.escapeShellArg stateDir}
        run ${pkgs.coreutils}/bin/install -m600 $VERBOSE_ARG -- \
          ${lib.escapeShellArg tokenSourcePath} \
          ${lib.escapeShellArg tokenRuntimePath}
      fi
    '';

    systemd.user.services.quicktui = {
      Unit = {
        Description = "QuickTUI server for remote tmux access over the tailnet";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
        # Stay cleanly inactive until the token has been placed in secrets/.
        ConditionPathExists = tokenRuntimePath;
      };

      Service = {
        Type = "simple";
        ExecStartPre = "${renderConfig}/bin/quicktui-render-config";
        ExecStart = "${pkgs.quicktui}/bin/quicktui-server --config ${configPath}";
        Restart = "on-failure";
        RestartSec = "5s";
        # Intentionally left unsandboxed, unlike the other user services here.
        # quicktui starts the tmux server itself whenever none is running, and
        # every remote pane then inherits this unit's execution context:
        # NoNewPrivileges would break sudo in those panes, PrivateTmp would hand
        # them a different /tmp than the desktop session, ProtectSystem would
        # make /etc read-only for them, and UMask would change the permissions
        # of files they create. Confidentiality is handled by writing the
        # rendered config 0600 inside the 0700 state directory instead.
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
