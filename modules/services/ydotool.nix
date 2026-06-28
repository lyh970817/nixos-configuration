{ pkgs, ... }:

let
  socketPath = "/run/ydotoold/socket";
  ydotooldForUser = pkgs.writeShellScript "ydotoold-andongni" ''
    uid="$(${pkgs.coreutils}/bin/id -u andongni)"
    gid="$(${pkgs.coreutils}/bin/id -g andongni)"
    exec ${pkgs.ydotool}/bin/ydotoold \
      --socket-path=${socketPath} \
      --socket-own="$uid:$gid" \
      --socket-perm=0660
  '';
in
{
  boot.kernelModules = [ "uinput" ];

  environment.systemPackages = [ pkgs.ydotool ];
  environment.sessionVariables.YDOTOOL_SOCKET = socketPath;

  services.udev.extraRules = ''
    KERNEL=="uinput", GROUP="uinput", MODE="0660", TAG+="uaccess"
  '';

  systemd.services.ydotoold = {
    description = "ydotool daemon";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = ydotooldForUser;
      Restart = "on-failure";
      RestartSec = "1s";
      RuntimeDirectory = "ydotoold";
    };
  };
}
