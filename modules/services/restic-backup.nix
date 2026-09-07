{
  config,
  pkgs,
  lib,
  ...
}:

let
  user = "andongni";
  home = config.users.users.${user}.home;
  configDir = config.portable.configDir;

  # restic has no native Yandex Disk backend, so rclone is the transport, not
  # an alternative to anything. It never sees plaintext: restic chunks,
  # deduplicates and encrypts locally, and hands rclone opaque pack files.
  rcloneConfigFile = "${configDir}/secrets/rclone.conf";
  homePasswordFile = "${configDir}/secrets/restic-password";
  archivePasswordFile = "${configDir}/secrets/restic-archive-password";

  homeRepository = "rclone:yandex:restic/home";
  archiveRepository = "rclone:yandex:restic/archive";
  statusDir = "${home}/.cache/sync-status";

  # Two repositories, because these are different lifecycles rather than two
  # halves of one. `home` holds live data on a rolling retention. `archive`
  # holds the only remaining copy of things deleted from disk, and is never
  # forgotten or pruned -- a normal retention policy applied to it would
  # silently garbage-collect the archive once its snapshot aged out.

  # Derived from a full inventory of $HOME (282 GB across 3.9M entries).
  # Everything here regenerates from something else, and together it accounts
  # for ~135 GB and ~1.8M of those entries.
  excludes = [
    # Caches and build artifacts. ~/.cache alone is 50 GB / 1.25M files.
    ".cache"
    ".npm"
    ".direnv"
    "__pycache__"
    "node_modules"
    ".venv"
    "venv"
    ".local/share/Trash"
    "go/pkg"
    ".cargo/registry"
    ".rustup"
    ".gradle"
    ".m2"
    "result"
    "result-*"

    # Container images, re-pullable. 19.3 GB in 160 files.
    "${home}/.apptainer"

    # Agent logs, rewritten constantly and worthless to restore.
    "${home}/.codex/logs_*.sqlite"

    # The sync daemon's own upload buffer -- transient state, not data.
    # Currently a 1.7 GB randomly-named temp file. Restoring it would only
    # confuse the daemon on next start.
    "${home}/Yandex.Disk/.sync"

    # Disk images. Exactly one file matches today, at 44.1 GB. Note that a
    # by-extension rule was checked against the inventory first: there are no
    # .mkv files anywhere in $HOME, and ".ts" would have matched 41,441
    # TypeScript sources rather than any video.
    "*.iso"
  ];
  excludeFile = pkgs.writeText "restic-home-excludes" (lib.concatStringsSep "\n" excludes);

  # Kept deliberately, against their size: every git repository (working trees
  # carry uncommitted work and several branches hold unpushed commits), agent
  # worktrees, all duckdb files, and ~/Yandex.Disk in full -- sync is not
  # backup, and its only other protection is a trash whose retention Yandex
  # does not document.

  resticEnv = repository: passwordFile: ''
    export PATH=${lib.makeBinPath [ pkgs.rclone ]}:$PATH
    export RESTIC_REPOSITORY=${lib.escapeShellArg repository}
    export RESTIC_PASSWORD_FILE=${lib.escapeShellArg passwordFile}
    export RCLONE_CONFIG=${lib.escapeShellArg rcloneConfigFile}
  '';

  # Wrappers so manual work (snapshots, restore, mount, check) does not mean
  # re-typing four environment variables under pressure.
  restic-home = pkgs.writeShellScriptBin "restic-home" ''
    ${resticEnv homeRepository homePasswordFile}
    exec ${pkgs.restic}/bin/restic "$@"
  '';

  restic-archive = pkgs.writeShellScriptBin "restic-archive" ''
    ${resticEnv archiveRepository archivePasswordFile}
    exec ${pkgs.restic}/bin/restic "$@"
  '';

  # Retention keeps the fine granularity the 15-minute cadence exists to
  # provide: a full day of it, then thinning out.
  retention = [
    "--keep-last 96"
    "--keep-hourly 48"
    "--keep-daily 14"
    "--keep-weekly 8"
    "--keep-monthly 24"
  ];

  restic-prune-home = pkgs.writeShellScriptBin "restic-prune-home" ''
    set -euo pipefail
    ${resticEnv homeRepository homePasswordFile}
    ${pkgs.restic}/bin/restic forget ${lib.concatStringsSep " " retention}
    # Prune rewrites pack files containing unreferenced chunks, which over a
    # remote means downloading and re-uploading them. --max-unused buys
    # tolerance for some slack instead of compacting aggressively.
    ${pkgs.restic}/bin/restic prune --max-unused 10%
  '';

  restic-backup-status = pkgs.writeShellApplication {
    name = "restic-backup-status";
    runtimeInputs = with pkgs; [
      coreutils
      jq
      restic
      rclone
      util-linux
    ];
    text = ''
      status_dir="''${SYNC_STATUS_DIR:-${statusDir}}"
      status_file="$status_dir/restic.json"
      lock_file="$status_dir/.restic.lock"
      run_dir=/run/restic-backups-home
      fifo="$run_dir/status-stream"
      snapshot_marker="$run_dir/status-snapshot"
      install -d -m 700 "$status_dir"

      last_success=
      if [[ -r "$status_file" ]]; then
        last_success=$(jq -r '.last_success // empty' "$status_file" 2>/dev/null || true)
      fi
      started_at=$(date --utc +%Y-%m-%dT%H:%M:%SZ)

      publish() {
        local state="$1" progress="$2" total="$3" started="$4"
        (
          flock 9
          local tmp updated_at
          updated_at=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
          tmp=$(mktemp "$status_dir/.restic.XXXXXX")
          jq -n \
            --arg state "$state" \
            --arg progress "$progress" \
            --arg total "$total" \
            --arg started "$started" \
            --arg last_success "$last_success" \
            --arg updated_at "$updated_at" '
              {
                version: 1,
                service: "restic",
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
        ) 9> "$lock_file"
      }

      heartbeat() {
        (
          flock 9
          if [[ -r "$status_file" ]] && jq -e '.state == "active" or .state == "scanning"' "$status_file" >/dev/null; then
            local tmp updated_at
            updated_at=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
            tmp=$(mktemp "$status_dir/.restic.XXXXXX")
            jq --arg updated_at "$updated_at" '.updated_at = $updated_at' "$status_file" > "$tmp"
            chmod 600 "$tmp"
            mv -f "$tmp" "$status_file"
          fi
        ) 9> "$lock_file"
      }

      parse_stream() {
        local line message_type progress total snapshot_id
        while IFS= read -r line; do
          printf '%s\n' "$line"
          message_type=$(jq -r '.message_type // empty' <<< "$line" 2>/dev/null || true)
          case "$message_type" in
            status)
              progress=$(jq -r '.bytes_done // empty' <<< "$line")
              total=$(jq -r '.total_bytes // empty' <<< "$line")
              if [[ "$progress" =~ ^[0-9]+$ && "$total" =~ ^[1-9][0-9]*$ ]]; then
                publish active "$progress" "$total" "$started_at"
              else
                heartbeat
              fi
              ;;
            summary)
              snapshot_id=$(jq -r '.snapshot_id // empty' <<< "$line")
              if [[ -n "$snapshot_id" ]]; then
                printf '%s\n' "$snapshot_id" > "$snapshot_marker"
              fi
              ;;
          esac
        done
      }

      cleanup() {
        if [[ -n "''${heartbeat_pid:-}" ]]; then
          kill "$heartbeat_pid" 2>/dev/null || true
          wait "$heartbeat_pid" 2>/dev/null || true
        fi
        rm -f "$fifo" "$snapshot_marker"
      }
      trap cleanup EXIT
      trap 'publish failed "" "" ""; exit 1' HUP INT TERM

      rm -f "$fifo" "$snapshot_marker"
      mkfifo "$fifo"
      publish scanning "" "" "$started_at"
      parse_stream < "$fifo" &
      parser_pid=$!

      restic backup --json --exclude-caches \
        --exclude-file=${excludeFile} \
        --files-from="$run_dir/includes" > "$fifo" &
      restic_pid=$!

      (
        while kill -0 "$restic_pid" 2>/dev/null; do
          sleep 30
          if kill -0 "$restic_pid" 2>/dev/null; then
            heartbeat
          fi
        done
      ) &
      heartbeat_pid=$!

      set +e
      wait "$restic_pid"
      restic_exit=$?
      wait "$parser_pid"
      parser_exit=$?
      set -e
      kill "$heartbeat_pid" 2>/dev/null || true
      wait "$heartbeat_pid" 2>/dev/null || true
      heartbeat_pid=

      if (( restic_exit == 0 && parser_exit == 0 )) && [[ -s "$snapshot_marker" ]]; then
        last_success=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
        publish finished "" "" ""
        exit 0
      fi

      publish failed "" "" ""
      if (( restic_exit == 0 )); then
        exit 1
      fi
      exit "$restic_exit"
    '';
  };

  secretsPresent = [
    rcloneConfigFile
    homePasswordFile
  ];
in
{
  services.restic.backups.home = {
    inherit user;
    repository = homeRepository;
    passwordFile = homePasswordFile;
    rcloneConfigFile = rcloneConfigFile;
    initialize = true;
    paths = [ home ];
    exclude = excludes;
    extraBackupArgs = [ "--exclude-caches" ];
    progressFps = 0.1;

    # Every 15 minutes rather than daily. The scan is not the cost -- walking
    # all 3.9M entries of $HOME measures at well under a second warm -- so the
    # per-run overhead is a couple of seconds of remote round trips, and the
    # payoff is that a file created and destroyed between two dailies is no
    # longer invisible to every tier at once.
    timerConfig = {
      OnCalendar = "*:0/15";
      Persistent = true;
      RandomizedDelaySec = "60";
    };

    # Deliberately no pruneOpts: the NixOS module would then forget and prune
    # after *every* backup, and prune is the one genuinely expensive operation
    # over a network repository. It runs monthly on its own timer below.
  };

  # Stay cleanly inactive until the credentials have been placed in secrets/,
  # so a rebuild on a fresh checkout is a no-op rather than a failing unit.
  systemd.services.restic-backups-home = {
    unitConfig.ConditionPathExists = secretsPresent;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig.ExecStart = lib.mkForce [ "${restic-backup-status}/bin/restic-backup-status" ];
  };

  systemd.services.restic-prune-home = {
    description = "Forget and prune the Yandex restic home repository";
    unitConfig.ConditionPathExists = secretsPresent;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      ExecStart = "${restic-prune-home}/bin/restic-prune-home";
    };
  };

  systemd.timers.restic-prune-home = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  environment.systemPackages = [
    pkgs.restic
    pkgs.rclone
    pkgs.yandex-trash
    restic-home
    restic-archive
  ];
}
