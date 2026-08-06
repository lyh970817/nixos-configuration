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
    environment.systemPackages = [ pkgs.sshfs ];

    # Pre-create the mountpoint so the automount unit has somewhere to hook.
    systemd.tmpfiles.rules = [
      "d ${mountPoint} 0755 andongni users -"
    ];

    fileSystems.${mountPoint} = {
      device = "andongni@${peer}:/home/andongni";
      fsType = "fuse.sshfs";
      options = [
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
        # Lazy automount: stays unmounted (and boot never waits on the peer
        # being reachable) until the directory is first accessed.
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
        "x-systemd.mount-timeout=10s"
      ];
    };
  };
}
