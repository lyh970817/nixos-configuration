{ ... }:

{
  # Claude Desktop's Cowork mode runs an accel=kvm QEMU guest (see
  # home/programs/claude-desktop.nix). The FHS package bundles qemu_kvm,
  # OVMF, and virtiofsd, but vhost_vsock is a host kernel module it can't
  # bring itself; /dev/kvm access comes from each host's own kvm module
  # plus the andongni user's kvm group membership.
  boot.kernelModules = [ "vhost_vsock" ];
}
