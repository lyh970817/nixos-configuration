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
    ];
    text = ''
      cache_path=${lib.escapeShellArg codexbarCachePath}
      cache_dir=$(dirname "$cache_path")
      install -d -m 700 "$cache_dir"

      tmp_path=$(mktemp "$cache_dir/.usage.json.XXXXXX")
      trap 'rm -f "$tmp_path"' EXIT
      response=$(${pkgs.codexbar}/bin/codexbar usage \
        --provider both \
        --source oauth \
        --format json \
        --no-color)
      printf '%s\n' "$response" > "$tmp_path"
      chmod 600 "$tmp_path"
      mv -f "$tmp_path" "$cache_path"
      trap - EXIT
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
      Requires = [ "codexbar.service" ];
      After = [ "codexbar.service" ];
    };

    Timer = {
      OnBootSec = "15s";
      OnUnitActiveSec = "60s";
      Unit = "codexbar-refresh.service";
    };

    Install.WantedBy = [ "timers.target" ];
  };
}
