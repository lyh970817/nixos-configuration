# Mounts the peer machine's home directory over SSHFS, in both directions:
# each side's portable.peerHost already names the *other* machine (remote's
# peerHost is "home"; home's peerHost is the remote's Tailscale name), so
# using that value both as the SSH target and as the local mountpoint name
# gives the reciprocal ~/home <-> ~/<remote-hostname> layout for free, with
# no role branching needed here.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  peer = config.portable.peerHost;
  mountPoint = "/home/andongni/${peer}";
in
{
  config = lib.mkIf (peer != "") {
    # Mount units run through PID 1, so keep sshfs in the filesystem-helper
    # path rather than relying on an fstab generator lookup.
    system.fsPackages = [ pkgs.sshfs ];

    # Pre-create the mountpoint so the automount unit has somewhere to hook.
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 andongni users -"
    ];

    # These are native units rather than an fstab row: systemd-fstab-generator
    # can otherwise block while resolving a stale active FUSE mount and leave
    # the automount definition absent after a reload.
    systemd.mounts = [
      {
        what = "andongni@${peer}:/home/andongni";
        where = mountPoint;
        type = "fuse.sshfs";
        # Match the fstab generator's network ordering, but attach it to the
        # mount rather than the automount so boot still installs a lazy trigger
        # without waiting for the peer.  These dependencies are pulled only
        # when directory access starts the SSHFS mount.
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        options = lib.concatStringsSep "," [
          # Tailscale SSH authenticates by tailnet node identity, not client
          # keys, so no IdentityFile/known_hosts management is needed here.
          "StrictHostKeyChecking=accept-new"
          "reconnect"
          "ServerAliveInterval=15"
          "ServerAliveCountMax=3"
          "uid=1000"
          "gid=100"
          "allow_other"
          "default_permissions"
          "_netdev"
        ];
        # Native equivalent of x-systemd.mount-timeout=10s.
        mountConfig.TimeoutSec = "10s";
      }
    ];

    systemd.automounts = [
      {
        where = mountPoint;
        # Activating this unit at boot installs the autofs trigger only; the
        # SSHFS mount itself still starts solely when the directory is used.
        wantedBy = [ "remote-fs.target" ];
        automountConfig.TimeoutIdleSec = "600s";
      }
    ];
  };
}
