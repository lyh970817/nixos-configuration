{
  config,
  lib,
  pkgs,
  ...
}:

let
  codexbarUrl = "http://127.0.0.1:8080/usage?provider=both";
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

  # Keep the serve cache warm independently of Fastfetch. Fastfetch only reads
  # the loopback endpoint and therefore never waits for provider requests.
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
      ExecStart = "${pkgs.curl}/bin/curl --noproxy '*' --fail --silent --show-error --connect-timeout 5 --max-time 30 --output /dev/null ${lib.escapeShellArg codexbarUrl}";
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
