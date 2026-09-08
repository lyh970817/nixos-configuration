{
  osConfig,
  pkgs,
  lib,
  ...
}:
let
  peer = osConfig.portable.peerHost;
  peerLabel = if osConfig.portable.role == "home" then "Laptop" else "Home Desktop";
  launcher = pkgs.writeShellApplication {
    name = "peer-dashboard";
    runtimeInputs = [
      pkgs.openssh
      pkgs.systemd
      pkgs.curl
      pkgs.gnused
      pkgs.xdg-utils
      pkgs.libnotify
    ];
    text = ''
      fail() {
        notify-send "${peerLabel} dashboard unavailable" "Check that the other machine is awake and connected to Tailscale."
        exit 1
      }
      systemctl --user start peer-dashboards.service
      case "''${1:-}" in
        mihomo)
          port=19090
          url='http://127.0.0.1:19090/ui/#/setup?hostname=127.0.0.1&port=19090&http=true'
          ;;
        sub-store)
          port=13001
          backend_path=$(ssh -o BatchMode=yes -o ConnectTimeout=10 ${lib.escapeShellArg peer} \
            "sed -n 's/^SUB_STORE_FRONTEND_BACKEND_PATH=//p' ~/.nixos-config/secrets/mihomo-cache/sub-store.env") || fail
          [[ "$backend_path" =~ ^/[a-zA-Z0-9_-]+$ ]] || fail
          url="http://127.0.0.1:13001/?api=http://127.0.0.1:13001$backend_path"
          ;;
        *) echo 'Usage: peer-dashboard mihomo|sub-store' >&2; exit 2 ;;
      esac
      ready=false
      for ((attempt=0; attempt<20; attempt++)); do
        if curl --noproxy '*' --silent --fail --max-time 1 "http://127.0.0.1:$port/" >/dev/null; then
          ready=true
          break
        fi
        sleep 1
      done
      "$ready" || fail
      exec xdg-open "$url"
    '';
  };
in
{
  systemd.user.services.peer-dashboards = {
    Unit.Description = "Private dashboard tunnels to ${peerLabel}";
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${pkgs.openssh}/bin/ssh -NT -o BatchMode=yes -o ConnectTimeout=10 -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -L 127.0.0.1:19090:127.0.0.1:9090 -L 127.0.0.1:13001:127.0.0.1:3001 ${peer}";
      Restart = "always";
      RestartSec = 5;
    };
  };
  home.packages = [
    launcher
  ]
  ++
    map
      (
        app:
        pkgs.makeDesktopItem {
          name = "peer-${app.id}";
          desktopName = "${app.label} — ${peerLabel}";
          comment = "Manage ${app.label} on ${peerLabel} over private SSH";
          exec = "${launcher}/bin/peer-dashboard ${app.id}";
          icon = "network-workgroup";
          categories = [ "Network" ];
        }
      )
      [
        {
          id = "mihomo";
          label = "Mihomo";
        }
        {
          id = "sub-store";
          label = "Sub-Store";
        }
      ];
}
