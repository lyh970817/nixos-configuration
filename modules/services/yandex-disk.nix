{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Yandex Disk daemon service
  systemd.services.yandex-disk = {
    description = "Yandex.Disk daemon";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "andongni";
      ExecStart = "${pkgs.yandex-disk}/bin/yandex-disk start --no-daemon --dir=${config.users.users.andongni.home}/Yandex.Disk";
      ExecStop = "${pkgs.yandex-disk}/bin/yandex-disk stop";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
