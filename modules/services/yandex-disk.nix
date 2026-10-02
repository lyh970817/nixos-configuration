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

  syncDir = "${home}/Yandex.Disk";
  configFile = "${home}/.config/yandex-disk/config.cfg";
  tokenFile = "${home}/.config/yandex-disk/token";

  # Exclude list. yandex-disk-excludes (./yandex-disk-excludes.py) scans
  # ~/Yandex.Disk and writes config.cfg's exclude-dirs= line; that line is
  # what the daemon is started with. The list is the union of:
  #   - staticExcludes below, always, whether or not the path exists;
  #   - tool-owned directories found by name: .nf-test and .nf-test-*,
  #     .nextflow, .worktrees, node_modules, .venv, __pycache__, .direnv,
  #     .pytest_cache, .mypy_cache, .ruff_cache, .gradle, and worktrees/
  #     directly under a dot directory (.claude/worktrees);
  #   - guarded names: target beside a Cargo.toml, build beside a
  #     (settings|build).gradle[.kts], work beside a .nextflow dir or
  #     .nextflow.log* file;
  #   - directories holding pyvenv.cfg, a signed CACHEDIR.TAG, or a
  #     .yandex-nosync marker file -- `touch DIR/.yandex-nosync` excludes DIR.
  # The scan never follows symlinks, crosses filesystems, or enters .git
  # (which itself stays synced). A path containing , " \ or a control
  # character cannot be written to the list: it is skipped with a warning.
  # Add a permanent entry to staticExcludes, path relative to ~/Yandex.Disk.
  # The list is rebuilt on every daemon start and every 30 minutes; a timer
  # run restarts the daemon only when a path not already excluded appears.
  staticExcludes = [
    # The encrypted backup repository.
    "restic"
    # Read-only companion checkouts that no churn rule matches.
    "Projects/Research/qc_dev/gwas/.references"
  ];

  yandexDiskExcludes = pkgs.writers.writePython3Bin "yandex-disk-excludes" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./yandex-disk-excludes.py);

  excludesArgs = lib.escapeShellArgs (
    [
      "--sync-dir=${syncDir}"
      "--config=${configFile}"
    ]
    ++ map (path: "--static=${path}") staticExcludes
  );

  # `yandex-disk start --no-daemon` never reads config.cfg (only the forking
  # `start` does, re-executing itself with --exclude-dirs), so the list is
  # passed on the command line from the exclude-dirs= line.
  yandexDiskStart = pkgs.writeShellApplication {
    name = "yandex-disk-start";
    runtimeInputs = [ pkgs.yandex-disk ];
    text = ''
      excludes=
      if [[ -r ${lib.escapeShellArg configFile} ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
          if [[ "$line" == exclude-dirs=* ]]; then
            excludes=''${line#exclude-dirs=}
            excludes=''${excludes#\"}
            excludes=''${excludes%\"}
            break
          fi
        done < ${lib.escapeShellArg configFile}
      fi
      # A config.cfg rewritten by `yandex-disk setup` loses the line; never
      # start without the static entries (the backup repository above all).
      if [[ -z "$excludes" ]]; then
        echo "yandex-disk-start: no exclude-dirs in config.cfg; using the static list" >&2
        excludes=${lib.escapeShellArg (lib.concatStringsSep "," staticExcludes)}
      fi
      exec yandex-disk start --no-daemon \
        --dir=${lib.escapeShellArg syncDir} \
        --auth=${lib.escapeShellArg tokenFile} \
        --exclude-dirs="$excludes"
    '';
  };

  # Runs as root after the refresh unit's ExecStart (as the user): exit 1
  # means a new path was added to the list, which the daemon only reads at
  # start. try-restart leaves a deliberately stopped daemon stopped.
  restartOnNewExcludes = pkgs.writeShellScript "yandex-disk-restart-on-new-excludes" ''
    if [[ "$EXIT_CODE" == exited && "$EXIT_STATUS" == 1 ]]; then
      exec ${pkgs.systemd}/bin/systemctl try-restart --no-block yandex-disk.service
    fi
  '';

  # Exit 2 rather than 1 when the daemon is down: SuccessExitStatus=1 on the
  # refresh unit also applies to ExecCondition and would let 1 through.
  yandexDiskActive = pkgs.writeShellScript "yandex-disk-active" ''
    ${pkgs.systemd}/bin/systemctl is-active --quiet yandex-disk.service || exit 2
  '';

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
    unitConfig.ConditionPathExists = tokenFile;
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "andongni";
      # Refresh the list before each start. "-" and the timeout let the
      # daemon start on the previous list if the scan fails or stalls.
      ExecStartPre = "-${pkgs.coreutils}/bin/timeout 60 ${yandexDiskExcludes}/bin/yandex-disk-excludes ${excludesArgs}";
      ExecStart = "${yandexDiskStart}/bin/yandex-disk-start";
      ExecStop = "${pkgs.yandex-disk}/bin/yandex-disk stop";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.yandex-disk-excludes = {
    description = "Refresh the Yandex.Disk exclude list";
    after = [ "yandex-disk.service" ];
    unitConfig.ConditionPathExists = tokenFile;
    serviceConfig = {
      Type = "oneshot";
      User = user;
      # Nothing to refresh while the daemon is stopped; its next start
      # rebuilds the list anyway.
      ExecCondition = "${yandexDiskActive}";
      ExecStart = "${yandexDiskExcludes}/bin/yandex-disk-excludes --only-if-added ${excludesArgs}";
      # Exit 1 means the list changed and was written.
      SuccessExitStatus = "1";
      ExecStopPost = "+${restartOnNewExcludes}";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.yandex-disk-excludes = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/30";
      Persistent = true;
      RandomizedDelaySec = "2min";
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
