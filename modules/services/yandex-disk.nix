{
  config,
  pkgs,
  lib,
  ...
}:

let
  user = "andongni";
  home = config.users.users.${user}.home;
  statusDir = "${home}/.cache/sync-status";

  yandexDiskStatus = pkgs.writeShellApplication {
    name = "yandex-disk-status";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      jq
      systemd
      yandex-disk
    ];
    text = ''
      status_dir="''${SYNC_STATUS_DIR:-${statusDir}}"
      status_file="$status_dir/yandex-disk.json"
      install -d -m 700 "$status_dir"

      now=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
      previous_state=
      previous_start=
      last_success=
      if [[ -r "$status_file" ]]; then
        previous_state=$(jq -r '.state // empty' "$status_file" 2>/dev/null || true)
        previous_start=$(jq -r '.started_at // empty' "$status_file" 2>/dev/null || true)
        last_success=$(jq -r '.last_success // empty' "$status_file" 2>/dev/null || true)
      fi

      publish() {
        local state="$1" progress="$2" total="$3" started="$4" tmp
        tmp=$(mktemp "$status_dir/.yandex-disk.XXXXXX")
        jq -n \
          --arg state "$state" \
          --arg progress "$progress" \
          --arg total "$total" \
          --arg started "$started" \
          --arg last_success "$last_success" \
          --arg updated_at "$now" '
            {
              version: 1,
              service: "yandex-disk",
              state: $state,
              progress_bytes: (if $progress == "" then null else ($progress | tonumber) end),
              total_bytes: (if $total == "" then null else ($total | tonumber) end),
              started_at: (if $started == "" then null else $started end),
              last_success: (if $last_success == "" then null else $last_success end),
              updated_at: $updated_at
            }
          ' > "$tmp"
        chmod 600 "$tmp"
        mv -f "$tmp" "$status_file"
      }

      if ! output=$(LC_ALL=C timeout 3s yandex-disk status \
        --dir=${lib.escapeShellArg "${home}/Yandex.Disk"} \
        --auth=${lib.escapeShellArg "${home}/.config/yandex-disk/token"} 2>&1); then
        if systemctl is-failed --quiet yandex-disk.service; then
          publish failed "" "" ""
        elif systemctl is-active --quiet yandex-disk.service; then
          if [[ ! -r ${lib.escapeShellArg "${home}/Yandex.Disk/.sync/status"} ]]; then
            publish unavailable "" "" ""
            exit 0
          fi
          mapfile -t local_status < ${lib.escapeShellArg "${home}/Yandex.Disk/.sync/status"}
          main_pid=$(systemctl show yandex-disk.service --property MainPID --value)
          if [[ "''${local_status[0]:-}" != "$main_pid" ]]; then
            publish unavailable "" "" ""
            exit 0
          fi
          case "''${local_status[1]:-}" in
            busy | index)
              if [[ ( "$previous_state" == active || "$previous_state" == scanning ) && -n "$previous_start" ]]; then
                started_at="$previous_start"
              else
                started_at="$now"
              fi
              if [[ "''${local_status[1]}" == index ]]; then
                publish scanning "" "" "$started_at"
              else
                publish active "" "" "$started_at"
              fi
              ;;
            idle)
              if [[ "$previous_state" == active || "$previous_state" == scanning ]]; then
                last_success="$now"
              fi
              publish finished "" "" ""
              ;;
            *) publish unavailable "" "" "" ;;
          esac
        else
          publish unavailable "" "" ""
        fi
        exit 0
      fi

      core_state=$(sed -n 's/^Synchronization core status: //p' <<< "$output")
      case "$core_state" in
        busy | index)
          if [[ ( "$previous_state" == active || "$previous_state" == scanning ) && -n "$previous_start" ]]; then
            started_at="$previous_start"
          else
            started_at="$now"
          fi

          progress_bytes=
          total_bytes=
          progress=$(sed -n 's/^Sync progress: \([0-9.]*\) \([KMGTPE]*B\)\/ *\([0-9.]*\) \([KMGTPE]*B\).*/\1\t\2\t\3\t\4/p' <<< "$output")
          if [[ -n "$progress" ]]; then
            IFS=$'\t' read -r progress_value progress_unit total_value total_unit <<< "$progress"
            progress_bytes=$(numfmt --from=si "''${progress_value}''${progress_unit%B}" 2>/dev/null || true)
            total_bytes=$(numfmt --from=si "''${total_value}''${total_unit%B}" 2>/dev/null || true)
            if [[ ! "$progress_bytes" =~ ^[0-9]+$ || ! "$total_bytes" =~ ^[1-9][0-9]*$ ]]; then
              progress_bytes=
              total_bytes=
            fi
          fi
          if [[ "$core_state" == index ]]; then
            publish scanning "" "" "$started_at"
          else
            publish active "$progress_bytes" "$total_bytes" "$started_at"
          fi
          ;;
        idle)
          if [[ "$previous_state" == active || "$previous_state" == scanning ]]; then
            last_success="$now"
          fi
          publish finished "" "" ""
          ;;
        *)
          publish unavailable "" "" ""
          ;;
      esac
    '';
  };
in
{
  # Yandex Disk daemon service
  systemd.services.yandex-disk = {
    description = "Yandex.Disk daemon";
    after = [ "network.target" ];
    unitConfig.ConditionPathExists = "${config.users.users.andongni.home}/.config/yandex-disk/token";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "andongni";
      # Foreground mode needs explicit options; never sync the encrypted backup repository.
      ExecStart = "${pkgs.yandex-disk}/bin/yandex-disk start --no-daemon --dir=${config.users.users.andongni.home}/Yandex.Disk --auth=${config.users.users.andongni.home}/.config/yandex-disk/token --exclude-dirs=restic";
      ExecStop = "${pkgs.yandex-disk}/bin/yandex-disk stop";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Observe the daemon out of band: its status command can block on daemon or
  # cloud state, so no shell greeting ever calls it directly.
  systemd.services.yandex-disk-status = {
    description = "Publish Yandex.Disk synchronization status";
    after = [ "yandex-disk.service" ];
    unitConfig.ConditionPathExists = "${home}/.config/yandex-disk/token";
    serviceConfig = {
      Type = "oneshot";
      User = user;
      ExecStart = "${yandexDiskStatus}/bin/yandex-disk-status";
    };
  };

  systemd.timers.yandex-disk-status = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5s";
      OnUnitActiveSec = "30s";
      Unit = "yandex-disk-status.service";
    };
  };
}
