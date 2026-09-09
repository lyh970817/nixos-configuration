{
  config,
  pkgs,
  lib,
  ...
}:
let
  allowed = pkgs.writeShellApplication {
    name = "sync-power-allowed";
    runtimeInputs = [ pkgs.power-profiles-daemon ];
    text = ''
      [[ $(powerprofilesctl get) != power-saver ]] && exit 0
      for supply in /sys/class/power_supply/*; do
        if [[ -f "$supply/online" ]] && [[ $(< "$supply/online") == 1 ]]; then
          exit 0
        fi
      done
      exit 1
    '';
  };
  reconcile = pkgs.writeShellApplication {
    name = "sync-power-policy";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      marker=/run/sync-power-policy/paused
      if ${allowed}/bin/sync-power-allowed; then
        if [[ -e "$marker" ]]; then
          rm "$marker"
          systemctl start yandex-disk.service restic-backups-home.timer restic-prune-home.timer
          systemctl start --no-block restic-backups-home.service
        fi
      else
        touch "$marker"
        systemctl stop restic-backups-home.timer restic-prune-home.timer
        systemctl stop yandex-disk.service restic-backups-home.service restic-prune-home.service
      fi
    '';
  };
in
{
  config = lib.mkIf (config.portable.role == "remote") {
    # Conditions prevent timer/manual starts while the periodic reconciler
    # also stops work that was already running when power mode changed.
    systemd.services = {
      yandex-disk.serviceConfig.ExecCondition = "${allowed}/bin/sync-power-allowed";
      restic-backups-home.serviceConfig.ExecCondition = "${allowed}/bin/sync-power-allowed";
      restic-prune-home.serviceConfig.ExecCondition = "${allowed}/bin/sync-power-allowed";
      sync-power-policy = {
        description = "Pause laptop sync on battery in power-saver mode";
        after = [ "power-profiles-daemon.service" ];
        wants = [ "power-profiles-daemon.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${reconcile}/bin/sync-power-policy";
          RuntimeDirectory = "sync-power-policy";
          RuntimeDirectoryPreserve = "yes";
        };
      };
    };
    systemd.timers.sync-power-policy = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5s";
        OnUnitInactiveSec = "15s";
        AccuracySec = "1s";
      };
    };
  };
}
