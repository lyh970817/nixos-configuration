{ config, lib, ... }:

{
  # Claude Desktop's Cowork mode runs an accel=kvm QEMU guest (see
  # home/programs/claude-desktop.nix). The FHS package bundles qemu_kvm,
  # OVMF, and virtiofsd, but vhost_vsock is a host kernel module it can't
  # bring itself; /dev/kvm access comes from the existing kvm-amd module
  # plus the andongni user's kvm group membership.
  boot.kernelModules = lib.mkIf (config.portable.role == "home") [ "vhost_vsock" ];
}
