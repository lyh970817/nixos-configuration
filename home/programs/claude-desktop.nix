{
  pkgs,
  lib,
  osConfig,
  ...
}:

{
  # FHS variant, not plain claude-desktop: it bundles qemu_kvm, an OVMF
  # firmware compat shim, and virtiofsd so Cowork's VM boot gates resolve
  # without a system-wide libvirt/QEMU stack (see
  # modules/programs/claude-desktop.nix for the one host-side piece, the
  # vhost_vsock kernel module, that the FHS env can't provide itself).
  home.packages = lib.mkIf (osConfig.portable.role == "home") [ pkgs.claude-desktop-fhs ];
}
