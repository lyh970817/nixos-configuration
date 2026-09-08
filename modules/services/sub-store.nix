{ config, pkgs, ... }:
let
  environmentFile = "${config.portable.configDir}/secrets/mihomo-cache/sub-store.env";
  launcher = pkgs.writeShellApplication {
    name = "sub-store-ui";
    runtimeInputs = [
      pkgs.gnused
      pkgs.xdg-utils
    ];
    text = ''
      backend_path=$(sed -n 's/^SUB_STORE_FRONTEND_BACKEND_PATH=//p' ${environmentFile})
      test -n "$backend_path"
      exec xdg-open "http://127.0.0.1:3001/?api=http://127.0.0.1:3001$backend_path"
    '';
  };
in
{
  systemd.services.sub-store = {
    description = "Local Sub-Store subscription manager";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      SUB_STORE_BACKEND_API_HOST = "127.0.0.1";
      SUB_STORE_BACKEND_API_PORT = "3001";
      SUB_STORE_BACKEND_MERGE = "true";
      SUB_STORE_FRONTEND_PATH = "${pkgs.sub-store-frontend}";
      SUB_STORE_DATA_BASE_PATH = "/var/lib/sub-store";
    };
    serviceConfig = {
      ExecStart = "${pkgs.sub-store}/bin/sub-store";
      EnvironmentFile = environmentFile;
      DynamicUser = true;
      StateDirectory = "sub-store";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/sub-store";
      UMask = "0077";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      Restart = "on-failure";
      RestartSec = 3;
    };
  };

  environment.systemPackages = [
    launcher
    (pkgs.makeDesktopItem {
      name = "sub-store";
      desktopName = "Sub-Store";
      comment = "Manage Mihomo subscription links";
      exec = "${launcher}/bin/sub-store-ui";
      icon = "network-workgroup";
      categories = [ "Network" ];
    })
  ];
}
