# installer/iso.nix
#
# Configuration for the self-contained offline installer ISO (issue 07).
# Layered on top of nixpkgs' minimal installation-cd module (wired in
# flake.nix's `nixosConfigurations.installer`). Bakes a representative
# target closure -- the actual `system` output's toplevel, plus both
# vendors' CPU microcode -- into the ISO's own Nix store so `nixos-install`
# on the target machine builds only the cheap top-level derivation and
# fetches nothing. Also carries the whole git-tracked repo (flake +
# installer scripts) onto the ISO so `installer/install.sh` can run
# straight from the booted environment.
#
# See docs/portable-nixos-usb-installer-spec.md ("Installer (custom
# self-contained offline ISO)").
{
  config,
  pkgs,
  lib,
  self,
  targetToplevel,
  ...
}:
{
  # Short: isoImage.volumeID is "nixos-$EDITION-$RELEASE-$ARCH" and ISO9660
  # volume IDs are capped at 32 characters -- "portable-offline" overflows
  # that limit once the release/arch suffix is appended.
  isoImage.edition = "offline";
  # Default squashfs compression (zstd level 19) is slow at this closure
  # size; trade some image size for a build that finishes in reasonable
  # time.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  # hardware.enableRedistributableFirmware is already set in
  # configuration.nix, so firmware for both vendors rides along in
  # targetToplevel's own closure. Only the microcode packages need adding
  # explicitly here, since the target's own microcode enablement
  # (hardware.cpu.*.updateMicrocode) is host-specific and picked at install
  # time by the generated hardware facts, not baked into targetToplevel.
  hardware.cpu.intel.updateMicrocode = true;
  hardware.cpu.amd.updateMicrocode = true;

  isoImage.storeContents = [
    targetToplevel
    pkgs.microcode-intel
    pkgs.microcode-amd
  ];

  # Carry the config repo (flake + installer scripts) onto the ISO so the
  # operator can run `cd /etc/nixos-config && ./installer/install.sh`
  # straight from the booted environment.
  environment.etc."nixos-config".source = self;
  environment.systemPackages = [ pkgs.git ];

  # Offline by design: fail loud instead of silently trying the network if
  # something isn't in the baked closure.
  nix.settings.substituters = lib.mkForce [ ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
