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
    unitConfig.ConditionPathExists = "${config.users.users.andongni.home}/.config/yandex-disk/token";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      User = "andongni";
      # Foreground mode needs explicit options; never sync the encrypted backup repository.
      ExecStart = "${pkgs.yandex-disk}/bin/yandex-disk start --no-daemon --dir=${config.users.users.andongni.home}/Yandex.Disk --auth=${config.users.users.andongni.home}/.config/yandex-disk/token --exclude-dirs=restic";
      ExecStop = "${pkgs.yandex-disk}/bin/yandex-disk stop";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
