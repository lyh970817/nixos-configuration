{
  config,
  lib,
  pkgs,
  ...
}:

let
  providerPath = lib.makeBinPath [
    pkgs.codex
    pkgs.claude-code
  ];
  proxyEnvironment = [
    "HTTP_PROXY=http://127.0.0.1:7890"
    "HTTPS_PROXY=http://127.0.0.1:7890"
    "ALL_PROXY=socks5h://127.0.0.1:7890"
    "NO_PROXY=localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,100.64.0.0/10,.ts.net"
    "http_proxy=http://127.0.0.1:7890"
    "https_proxy=http://127.0.0.1:7890"
    "all_proxy=socks5h://127.0.0.1:7890"
    "no_proxy=localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,100.64.0.0/10,.ts.net"
  ];
  codexbarCachePath = "${config.home.homeDirectory}/.cache/codexbar/usage.json";
  claudeLimitWatchDisabledMarker = "${config.xdg.stateHome}/claude-limit-watch/disabled";
  codexbarRefresh = pkgs.writeShellApplication {
    name = "codexbar-refresh-cache";
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = ''
      cache_path=${lib.escapeShellArg codexbarCachePath}
      cache_dir=$(dirname "$cache_path")
      install -d -m 700 "$cache_dir"

      tmp_path=$(mktemp "$cache_dir/.usage.json.XXXXXX")
      trap 'rm -f "$tmp_path"' EXIT
      if response=$(${pkgs.codexbar}/bin/codexbar usage \
        --provider both \
        --source oauth \
        --format json \
        --no-color); then
        codexbar_status=0
      else
        codexbar_status=$?
      fi

      # A provider whose credentials have gone stale still comes back in the
      # array, but with a null usage object. Claude does this every time its
      # OAuth access token ages out, because CodexBar reads that token and
      # refuses to renew it — only the Claude CLI itself rewrites the file. Rather
      # than blank the row until the next Claude session, keep the last figures
      # this provider reported and let them stand in.
      # shellcheck disable=SC2016  # the $names below are jq variables, not shell ones
      merge_filter='
        def as_array: if type == "array" then . else [.] end;

        ($previous | as_array | map(select(.provider != null))) as $old
        | (as_array | map(select(.provider != null))) as $new
        | ([$old[].provider] - [$new[].provider]) as $dropped
        | ( $new
            | map(
                . as $entry
                | ($old | map(select(.provider == $entry.provider)) | first) as $prior
                | if ($entry.usage // null) != null then $entry
                  elif ($prior != null and ($prior.usage // null) != null) then $prior
                  else $entry
                  end
              )
          )
          + ($old | map(select(.provider as $p | ($dropped | index($p)) != null)))
      '

      if [ -n "$response" ] && printf '%s\n' "$response" | jq empty >/dev/null 2>&1; then
        previous='[]'
        if [ -r "$cache_path" ] && jq empty "$cache_path" >/dev/null 2>&1; then
          previous=$(cat "$cache_path")
        fi

        if ! printf '%s\n' "$response" \
          | jq --argjson previous "$previous" "$merge_filter" > "$tmp_path"; then
          printf 'merging cached usage failed; caching the raw response\n' >&2
          printf '%s\n' "$response" > "$tmp_path"
        fi
        chmod 600 "$tmp_path"
        mv -f "$tmp_path" "$cache_path"
        trap - EXIT

        if [ "$codexbar_status" -ne 0 ]; then
          printf 'codexbar usage exited with status %s; cached valid partial response\n' "$codexbar_status" >&2
        fi
        exit 0
      fi

      if [ "$codexbar_status" -eq 0 ]; then
        printf 'codexbar usage returned empty or invalid JSON; cache unchanged\n' >&2
        exit 1
      fi
      printf 'codexbar usage exited with status %s and returned empty or invalid JSON; cache unchanged\n' \
        "$codexbar_status" >&2
      exit "$codexbar_status"
    '';
  };
  claudeLimitWatch = pkgs.writeShellApplication {
    name = "claude-limit-watch";
    runtimeInputs = with pkgs; [
      herdr
      libnotify
      python3
    ];
    text = ''
      exec python3 ${../../scripts/claude-limit-watch.py} "$@"
    '';
  };
  claudeLimitWatchControl = pkgs.writeShellApplication {
    name = "claude-limit-watch-control";
    runtimeInputs = with pkgs; [
      coreutils
      libnotify
      systemd
    ];
    text = ''
      marker=${lib.escapeShellArg claudeLimitWatchDisabledMarker}
      path_unit=claude-limit-watch.path
      timer_unit=claude-limit-watch.timer
      service_unit=claude-limit-watch.service

      announce() {
        notify-send --app-name="Claude limit watch" "$1" "$2" || true
      }

      enable_watch() {
        rm -f "$marker"
        systemctl --user reset-failed "$path_unit" "$timer_unit" "$service_unit" \
          >/dev/null 2>&1 || true
        if systemctl --user start "$path_unit" "$timer_unit"; then
          announce "Claude watcher enabled" \
            "The five-hour limit watcher will resume Claude sessions after reset."
          return
        fi

        install -d -m 700 "$(dirname "$marker")"
        install -m 600 /dev/null "$marker"
        systemctl --user stop "$path_unit" "$timer_unit" "$service_unit" \
          >/dev/null 2>&1 || true
        announce "Claude watcher could not be enabled" \
          "Its previous disabled state has been restored."
        return 1
      }

      disable_watch() {
        install -d -m 700 "$(dirname "$marker")"
        install -m 600 /dev/null "$marker"
        disable_status=0
        systemctl --user stop "$path_unit" "$timer_unit" "$service_unit" \
          || disable_status=$?
        systemctl --user reset-failed "$path_unit" "$timer_unit" "$service_unit" \
          >/dev/null 2>&1 || true
        if [ "$disable_status" -eq 0 ]; then
          announce "Claude watcher disabled" \
            "Limit checks and automatic session resumes are stopped."
          return
        fi

        announce "Claude watcher disable was incomplete" \
          "The disabled preference was saved and will be enforced on the next activation."
        return 1
      }

      case "''${1:-toggle}" in
        enable)
          enable_watch
          ;;
        disable)
          disable_watch
          ;;
        toggle)
          if [ -e "$marker" ]; then
            enable_watch
          else
            disable_watch
          fi
          ;;
        status)
          if [ -e "$marker" ]; then
            printf 'disabled\n'
          else
            printf 'enabled\n'
          fi
          ;;
        *)
          printf 'usage: claude-limit-watch-control [enable|disable|toggle|status]\n' >&2
          exit 2
          ;;
      esac
    '';
  };

in
{
  home.packages = [
    pkgs.codexbar
    claudeLimitWatchControl
  ];

  systemd.user.services.codexbar = {
    Unit = {
      Description = "CodexBar local coding-agent usage server";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.codexbar}/bin/codexbar serve --host 127.0.0.1 --port 8080 --refresh-interval 60 --request-timeout 10";
      Environment = [
        "CODEX_HOME=${config.home.homeDirectory}/.codex"
        "CLAUDE_CONFIG_DIR=${config.home.homeDirectory}/.config/claude"
        "PATH=${providerPath}"
      ]
      ++ proxyEnvironment;
      Restart = "on-failure";
      RestartSec = "5s";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "full";
    };

    Install.WantedBy = [ "default.target" ];
  };

  # Refresh the snapshot cache independently of Fast Fetch. Fast Fetch only
  # reads this local file and never waits for provider requests.
  systemd.user.services.codexbar-refresh = {
    Unit = {
      Description = "Refresh CodexBar usage cache";
      Requires = [ "codexbar.service" ];
      After = [
        "codexbar.service"
        "network-online.target"
      ];
    };

    Service = {
      Type = "oneshot";
      Environment = [
        "CODEX_HOME=${config.home.homeDirectory}/.codex"
        "CLAUDE_CONFIG_DIR=${config.home.homeDirectory}/.config/claude"
        "PATH=${providerPath}"
      ]
      ++ proxyEnvironment;
      ExecStart = "${codexbarRefresh}/bin/codexbar-refresh-cache";
    };
  };

  systemd.user.timers.codexbar-refresh = {
    Unit = {
      Description = "Refresh CodexBar usage cache periodically";
      # The triggered service owns the dependency on codexbar.service. Keeping
      # it off the timer prevents a Home Manager restart of CodexBar from
      # stopping the schedule without starting it again.
    };

    Timer = {
      OnBootSec = "15s";
      OnUnitActiveSec = "60s";
      Unit = "codexbar-refresh.service";
    };

    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.claude-limit-watch = {
    Unit = {
      Description = "Observe Claude's five-hour usage limit";
      ConditionPathExists = "!${claudeLimitWatchDisabledMarker}";
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${claudeLimitWatch}/bin/claude-limit-watch";
      StateDirectory = "claude-limit-watch";
      StateDirectoryMode = "0700";
      UMask = "0077";
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
  };

  # Atomic cache replacements wake this path unit. The timer independently
  # advances persisted reset schedules, even when Claude OAuth data goes stale.
  systemd.user.paths.claude-limit-watch = {
    Unit = {
      Description = "Watch the CodexBar cache for Claude limit changes";
      ConditionPathExists = "!${claudeLimitWatchDisabledMarker}";
    };
    Path = {
      PathChanged = codexbarCachePath;
      Unit = "claude-limit-watch.service";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.timers.claude-limit-watch = {
    Unit = {
      Description = "Check Claude's persisted limit reset schedule";
      ConditionPathExists = "!${claudeLimitWatchDisabledMarker}";
    };
    Timer = {
      OnCalendar = "*-*-* *:*:00";
      AccuracySec = "1s";
      Persistent = true;
      Unit = "claude-limit-watch.service";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Reapply the user's persisted preference after the unit reload. The units
  # remain declaratively enabled: disabling a Home Manager unit through
  # systemctl would also remove its managed unit-file symlink. The marker and
  # unit conditions provide the durable disabled state instead.
  home.activation.reconcileClaudeLimitWatch = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    if [ -e ${lib.escapeShellArg claudeLimitWatchDisabledMarker} ]; then
      run ${pkgs.systemd}/bin/systemctl --user stop \
        claude-limit-watch.path claude-limit-watch.timer claude-limit-watch.service
      run ${pkgs.systemd}/bin/systemctl --user reset-failed \
        claude-limit-watch.path claude-limit-watch.timer claude-limit-watch.service
    else
      run ${pkgs.systemd}/bin/systemctl --user reset-failed \
        claude-limit-watch.path claude-limit-watch.timer claude-limit-watch.service
      run ${pkgs.systemd}/bin/systemctl --user start \
        claude-limit-watch.path claude-limit-watch.timer
    fi
  '';
}
