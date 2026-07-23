{ pkgs, ... }:

let
  renderConfig = pkgs.writeShellApplication {
    name = "cli-proxy-api-render-config";
    runtimeInputs = with pkgs; [
      coreutils
      openssl
    ];
    text = ''
            set -euo pipefail
            umask 077

            state_home="''${XDG_STATE_HOME:-$HOME/.local/state}"
            data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"
            runtime_home="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
            state_dir="$state_home/cli-proxy-api"
            auth_dir="$data_home/cli-proxy-api/auth"
            runtime_dir="$runtime_home/cli-proxy-api"
            key_file="$state_dir/client-key"
            config_file="$runtime_dir/config.yaml"

            install -d -m 0700 "$state_dir" "$auth_dir" "$runtime_dir"

            if [ ! -s "$key_file" ]; then
              key_tmp="$(mktemp "$state_dir/client-key.XXXXXX")"
              openssl rand -hex 32 > "$key_tmp"
              chmod 0600 "$key_tmp"
              if [ ! -s "$key_file" ]; then
                mv -f "$key_tmp" "$key_file"
              else
                rm -f "$key_tmp"
              fi
            fi
            chmod 0600 "$key_file"
            client_key="$(tr -d '\r\n' < "$key_file")"

            config_tmp="$(mktemp "$runtime_dir/config.yaml.XXXXXX")"
            cat > "$config_tmp" <<EOF
      host: "127.0.0.1"
      port: 8317

      tls:
        enable: false
        cert: ""
        key: ""

      remote-management:
        allow-remote: false
        secret-key: ""
        disable-control-panel: true

      auth-dir: "$auth_dir"
      api-keys:
        - "$client_key"

      debug: false
      pprof:
        enable: false
        addr: "127.0.0.1:8316"

      plugins:
        enabled: false

      commercial-mode: false
      logging-to-file: false
      logs-max-total-size-mb: 0
      usage-statistics-enabled: false
      proxy-url: "socks5://127.0.0.1:7890"
      ws-auth: true

      oauth-model-alias:
        codex:
          - name: "gpt-5.6-sol"
            alias: "claude-gpt-5-6-sol-low"
            fork: true
          - name: "gpt-5.6-sol"
            alias: "claude-gpt-5-6-sol-medium"
            fork: true
          - name: "gpt-5.6-sol"
            alias: "claude-gpt-5-6-sol-high"
            fork: true
          - name: "gpt-5.6-sol"
            alias: "claude-gpt-5-6-sol-xhigh"
            fork: true
          - name: "gpt-5.6-sol"
            alias: "claude-gpt-5-6-sol-max"
            fork: true
          - name: "gpt-5.6-terra"
            alias: "claude-gpt-5-6-terra-low"
            fork: true
          - name: "gpt-5.6-terra"
            alias: "claude-gpt-5-6-terra-medium"
            fork: true
          - name: "gpt-5.6-terra"
            alias: "claude-gpt-5-6-terra-high"
            fork: true
          - name: "gpt-5.6-terra"
            alias: "claude-gpt-5-6-terra-xhigh"
            fork: true
          - name: "gpt-5.6-terra"
            alias: "claude-gpt-5-6-terra-max"
            fork: true
          - name: "gpt-5.6-luna"
            alias: "claude-gpt-5-6-luna-low"
            fork: true
          - name: "gpt-5.6-luna"
            alias: "claude-gpt-5-6-luna-medium"
            fork: true
          - name: "gpt-5.6-luna"
            alias: "claude-gpt-5-6-luna-high"
            fork: true
          - name: "gpt-5.6-luna"
            alias: "claude-gpt-5-6-luna-xhigh"
            fork: true
          - name: "gpt-5.6-luna"
            alias: "claude-gpt-5-6-luna-max"
            fork: true

      payload:
        override:
          - models:
              - name: "claude-gpt-5-6-sol-low"
                protocol: "codex"
              - name: "claude-gpt-5-6-terra-low"
                protocol: "codex"
              - name: "claude-gpt-5-6-luna-low"
                protocol: "codex"
            params:
              "reasoning.effort": "low"
          - models:
              - name: "claude-gpt-5-6-sol-medium"
                protocol: "codex"
              - name: "claude-gpt-5-6-terra-medium"
                protocol: "codex"
              - name: "claude-gpt-5-6-luna-medium"
                protocol: "codex"
            params:
              "reasoning.effort": "medium"
          - models:
              - name: "claude-gpt-5-6-sol-high"
                protocol: "codex"
              - name: "claude-gpt-5-6-terra-high"
                protocol: "codex"
              - name: "claude-gpt-5-6-luna-high"
                protocol: "codex"
            params:
              "reasoning.effort": "high"
          - models:
              - name: "claude-gpt-5-6-sol-xhigh"
                protocol: "codex"
              - name: "claude-gpt-5-6-terra-xhigh"
                protocol: "codex"
              - name: "claude-gpt-5-6-luna-xhigh"
                protocol: "codex"
            params:
              "reasoning.effort": "xhigh"
          - models:
              - name: "claude-gpt-5-6-sol-max"
                protocol: "codex"
              - name: "claude-gpt-5-6-terra-max"
                protocol: "codex"
              - name: "claude-gpt-5-6-luna-max"
                protocol: "codex"
            params:
              "reasoning.effort": "max"
      EOF

            chmod 0600 "$config_tmp"
            mv -f "$config_tmp" "$config_file"
    '';
  };

  codexLogin = pkgs.writeShellApplication {
    name = "cli-proxy-api-codex-login";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      set -euo pipefail
      runtime_home="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

      ${renderConfig}/bin/cli-proxy-api-render-config
      systemctl --user start cli-proxy-api.service
      ${pkgs.cli-proxy-api}/bin/cli-proxy-api \
        -config "$runtime_home/cli-proxy-api/config.yaml" \
        -codex-login "$@"
    '';
  };
in
{
  home.packages = [
    pkgs.cli-proxy-api
    codexLogin
  ];

  systemd.user.services.cli-proxy-api = {
    Unit = {
      Description = "Local CLIProxyAPI gateway for Claude Code GPT-5.6 profile";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      Type = "simple";
      UMask = "0077";
      RuntimeDirectory = "cli-proxy-api";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = "${renderConfig}/bin/cli-proxy-api-render-config";
      ExecStart = "${pkgs.cli-proxy-api}/bin/cli-proxy-api -config %t/cli-proxy-api/config.yaml";
      Restart = "on-failure";
      RestartSec = "2s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "full";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
