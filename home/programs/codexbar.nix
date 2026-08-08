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

in
{
  home.packages = [ pkgs.codexbar ];

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
      # Requires alone adds no ordering edge. An After= here closes an ordering
      # cycle (timers.target -> this timer -> codexbar.service -> basic.target
      # -> timers.target) that made systemd drop timers.target from the initial
      # user transaction at every login.
      Requires = [ "codexbar.service" ];
    };

    Timer = {
      OnBootSec = "15s";
      OnUnitActiveSec = "60s";
      Unit = "codexbar-refresh.service";
    };

    Install.WantedBy = [ "timers.target" ];
  };
}
