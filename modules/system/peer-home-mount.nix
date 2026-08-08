# Mounts the peer machine's home directory over SSHFS, in both directions:
# each side's portable.peerHost already names the *other* machine (remote's
# peerHost is "home"; home's peerHost is the remote's Tailscale name), so
# using that value as the SSH target and visible link name gives the reciprocal
# ~/home <-> ~/<remote-hostname> layout without nesting either native mount in
# the home tree exported back to its peer.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  peer = config.portable.peerHost;
  mountRoot = "/run/mount/peer-home";
  mountPoint = "${mountRoot}/${peer}";
  homeLink = "/home/andongni/${peer}";
in
{
  config = lib.mkIf (peer != "") {
    # Mount units run through PID 1, so keep sshfs in the filesystem-helper
    # path rather than relying on an fstab generator lookup.
    system.fsPackages = [ pkgs.sshfs ];

    # Keep the native automount outside the SFTP-exported home tree.  Convert
    # the former mountpoint to the stable link only during clean boot setup;
    # activation must not touch a still-mounted legacy path.
    systemd.tmpfiles.rules = [
      "L+! ${homeLink} - - - - ${mountPoint}"
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
        # PID 1 creates the root-owned 0755 mountpoint and parent directories;
        # SSHFS maps mounted content to andongni:users below.
        wantedBy = [ "remote-fs.target" ];
        automountConfig = {
          DirectoryMode = "0755";
          TimeoutIdleSec = "600s";
        };
      }
    ];
  };
}
