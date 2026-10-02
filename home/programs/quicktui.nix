{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  homeDir = config.home.homeDirectory;
  quicktui = lib.getExe pkgs.quicktui;

  # `--config` also chooses the data directory: the server keeps pairings
  # (pairing_auth.json), its E2E identity (e2e_identity.json), the relay binding
  # and agentbridge2/ beside the config file. It therefore has to survive
  # reboots ($XDG_RUNTIME_DIR is tmpfs and would silently un-pair every phone),
  # and the server refuses to run unless the directory is exactly 0700. This is
  # the directory the legacy server used; server2 keeps its e2e_identity.json
  # and migrates pairing_auth.json in place. The legacy `config`, `token` and
  # quicktui.db* files left there are no longer read.
  stateDir = "${homeDir}/.local/share/quicktui";
  configPath = "${stateDir}/config.toml";

  # Herdr is the only session backend. Writing `session_backends` by hand turns
  # off detection, so tmux is never added even though it is on PATH. The server
  # finds Herdr through `herdr_bin` first; pointing it at the wrapper rather than
  # the bare package keeps THEME_MODE resolution for a server QuickTUI has to
  # start itself. Running Herdr servers are reached through their sockets under
  # ~/.config/herdr (the default session and every named one, such as `remote`),
  # which this same-user, same-HOME unit shares; the server ignores
  # HERDR_SESSION and HERDR_SOCKET_PATH.
  #
  # Bind every interface rather than the tailnet address. modules/system/
  # networking.nix runs a default-deny firewall that does not list 8022 in
  # allowedTCPPorts and does trust tailscale0, so the socket is reachable only
  # over the tailnet and loopback. Naming the tailnet IP instead would hardcode
  # a machine-specific address and make the unit fail to start whenever
  # tailscaled has not finished bringing the interface up.
  #
  # Device pairing replaced the legacy access token: secrets/quicktui-token is
  # no longer read, and a `token` key would be stripped by the server anyway.
  settings = {
    addr = "0.0.0.0:8022";
    session_backend = "herdr";
    session_backends = "herdr";
    herdr_bin = "${config.programs.herdr.package}/bin/herdr";
  };
  configFile = (pkgs.formats.toml { }).generate "quicktui-config.toml" settings;

  # The server rewrites config.toml (it records the `*_auto` detection keys and
  # strips retired ones), so the file cannot be a read-only store symlink.
  # Re-rendering it on every start keeps it declarative; the in-app settings
  # that land in this file (such as files_enabled) therefore reset on restart.
  renderConfig = pkgs.writeShellApplication {
    name = "quicktui-render-config";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      umask 077
      state_dir=${lib.escapeShellArg stateDir}
      mkdir -p "$state_dir"
      chmod 0700 "$state_dir"
      config_tmp="$(mktemp "$state_dir/config.toml.XXXXXX")"
      cat ${configFile} > "$config_tmp"
      chmod 0600 "$config_tmp"
      mv -f "$config_tmp" ${lib.escapeShellArg configPath}
    '';
  };
in
{
  # Remote terminal access to this machine's Herdr sessions from the QuickTUI
  # app. Home role only: the QuickTUI free tier covers a single server, so the
  # portable laptop is left out until a Pro licence is in place.
  #
  # The binary is managed by Nix: never run `upgrade`, `service
  # install|uninstall|restart` or `config set` (which restarts the service).
  # They would write to the read-only store path or install a systemd unit
  # competing with the one below; bump pkgs/quicktui.nix instead.
  #
  # Pair a phone after the unit is running, choosing the tailscale0 address:
  #   quicktui-server pairing qrcode --select-address \
  #     --config ~/.local/share/quicktui/config.toml
  config = lib.mkIf (osConfig.portable.role == "home") {
    home.packages = [ pkgs.quicktui ];

    systemd.user.services.quicktui = {
      Unit = {
        Description = "QuickTUI server for remote Herdr access over the tailnet";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };

      Service = {
        Type = "simple";
        ExecStartPre = [
          "${renderConfig}/bin/quicktui-render-config"
          # Agent hooks stay off for every agent. Without a recorded "disabled"
          # intent, `serve` installs `quicktui-server ab2hook` entries into
          # Claude's settings.json and Codex's hooks.json on every start (and
          # into Grok, OpenCode, pi and Cursor configs). `hooks uninstall`
          # records that intent per agent under agentbridge2/ and removes only
          # entries QuickTUI itself owns, leaving other hooks alone. Running it
          # before each start keeps hooks off even if the app re-enables them.
          # It must succeed: without the intent the server would add hooks.
          "${quicktui} hooks uninstall --config ${configPath}"
        ];
        ExecStart = "${quicktui} serve --config ${configPath}";
        Restart = "on-failure";
        RestartSec = "5s";
        # At startup the server launches a default-session Herdr server when none
        # is running (the laptop's `remote` session does not count), and that
        # server lands in this unit's cgroup. Stop only the main process so a
        # restart, including one from a rebuild, does not kill those panes; the
        # next start reattaches to the surviving Herdr server.
        KillMode = "process";
        # Intentionally left unsandboxed, unlike the other user services here.
        # When no default-session Herdr server is running, QuickTUI starts one
        # itself, and every pane in it then inherits this unit's context:
        # NoNewPrivileges would break sudo in those panes, PrivateTmp would hand
        # them a different /tmp than the desktop session, ProtectSystem would
        # make /etc read-only for them, and UMask would change the permissions
        # of files they create. Confidentiality is handled by keeping the state
        # directory 0700 and every file in it 0600 instead.
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
