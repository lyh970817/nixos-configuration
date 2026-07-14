{ pkgs, ... }:

let
  mihomoSafeRebuild = pkgs.writeShellApplication {
    name = "mihomo-safe-rebuild";
    runtimeInputs = with pkgs; [
      coreutils
      git
      nix
      systemd
      util-linux
    ];
    text = builtins.readFile ../../scripts/mihomo-safe-rebuild.sh;
  };
in
{
  environment.systemPackages = [ mihomoSafeRebuild ];

  systemd.tmpfiles.rules = [
    "d /var/lib/mihomo-safe-rebuild 0700 root root -"
    "d /var/lib/mihomo-safe-rebuild/history 0700 root root -"
    "f /var/lib/mihomo-safe-rebuild/events.log 0600 root root -"
  ];

  systemd.services."mihomo-safe-rebuild-rollback@" = {
    description = "Roll back guarded Mihomo deployment %i";
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      ExecStart = "${mihomoSafeRebuild}/bin/mihomo-safe-rebuild rollback-from-timer %i";
    };
  };

  systemd.timers."mihomo-safe-rebuild-rollback@" = {
    description = "Fixed 120-second rollback deadline for guarded Mihomo deployment %i";
    timerConfig = {
      AccuracySec = "1s";
      OnActiveSec = "120s";
      Unit = "mihomo-safe-rebuild-rollback@%i.service";
    };
  };

  systemd.services.mihomo-safe-rebuild-boot-recovery = {
    description = "Recover any unconfirmed guarded Mihomo deployment after boot";
    wantedBy = [ "multi-user.target" ];
    before = [
      "network.target"
      "network-online.target"
    ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      ExecStart = "${mihomoSafeRebuild}/bin/mihomo-safe-rebuild boot-recovery";
    };
  };
}
