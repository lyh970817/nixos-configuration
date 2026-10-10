{
  pkgs,
  lib,
  osConfig,
  ...
}:

{
  # ChatGPT Desktop starts with the graphical session in the orchestrator
  # profile (~/.codex-desktop-orchestrator) and lands on workspace 9
  # (the `chatgpt-workspace-9` window rule in dotfiles/hypr/hyprland.lua). The
  # rule only applies at map time, so the window stays movable afterwards.
  #
  # Restart is deliberately `on-failure`, not `always`: Super+Shift+Q
  # (forcekillactive -> SIGKILL) is a unit failure and brings the app back on
  # workspace 9, while Super+Q (killactive -> a clean close) exits 0 and leaves
  # it down until the user launches it again.
  #
  # Home role only: the remote laptop should not autostart an Electron app at
  # login.
  config = lib.mkIf (osConfig.portable.role == "home") {
    systemd.user.services.chatgpt = {
      Unit = {
        Description = "ChatGPT Desktop (Orchestrator)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.chatgpt}/bin/chatgpt-orchestrator";
        Restart = "on-failure";
        RestartSec = "2s";
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # A dead refresh token fails silently: the window looks fine while the
    # phone's remote-control link and durable threads retry forever. The app
    # server logs each failure to its own CODEX_HOME, so poll that and alert at
    # most once every six hours until the profile is signed in again.
    systemd.user.services.chatgpt-auth-watch = {
      Unit.Description = "Alert when ChatGPT Desktop's sign-in has expired";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe (
          pkgs.writeShellApplication {
            name = "chatgpt-auth-watch";
            runtimeInputs = with pkgs; [
              coreutils
              libnotify
              sqlite
            ];
            text = ''
              db="$HOME/.codex-desktop-orchestrator/logs_2.sqlite"
              stamp="''${XDG_STATE_HOME:-$HOME/.local/state}/chatgpt-auth-watch.last"
              [ -r "$db" ] || exit 0
              failures=$(sqlite3 -readonly "$db" \
                "select count(*) from logs where ts > strftime('%s','now','-20 minutes')
                 and feedback_log_body like '%could not be refreshed%';") || exit 0
              [ "$failures" -gt 0 ] || exit 0
              if [ -e "$stamp" ] && [ $(( $(date +%s) - $(stat -c %Y "$stamp") )) -lt 21600 ]; then
                exit 0
              fi
              echo "ChatGPT Desktop sign-in expired ($failures refresh failures in 20 min)"
              notify-send -u critical "ChatGPT Desktop signed out" \
                "Remote access from the phone is down until the orchestrator profile signs in again." || true
              mkdir -p "$(dirname "$stamp")"
              touch "$stamp"
            '';
          }
        );
      };
    };
    systemd.user.timers.chatgpt-auth-watch = {
      Unit.Description = "Check ChatGPT Desktop's sign-in every 15 minutes";
      Timer = {
        OnStartupSec = "10min";
        OnUnitActiveSec = "15min";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
