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
  flakeInputs,
  ...
}:
let
  # Recursively collect the source store path (outPath) of every flake input,
  # direct and transitive, so the target machine can EVALUATE #system fully
  # offline. targetToplevel only bakes the config's runtime *closure*; the
  # eval itself still needs the nixpkgs/home-manager/... source trees, which
  # are not runtime deps and would otherwise be fetched from the network (and
  # fail, since the ISO forces substituters = []). The graph is a finite DAG
  # (follows point at existing nodes, nixpkgs bottoms out with no inputs), so
  # this terminates; lib.unique drops the redundant re-visits.
  collectInputSources =
    inputs:
    lib.concatLists (
      lib.mapAttrsToList (
        _: input:
        (lib.optional (input ? outPath) input.outPath)
        ++ (lib.optionals (input ? inputs) (collectInputSources input.inputs))
      ) inputs
    );
  inputSources = lib.unique (collectInputSources flakeInputs);
in
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
  ]
  # Flake input source trees, so `nixos-install --flake ...#system` can
  # re-evaluate the generic config against the target's generated facts
  # without any network access. See collectInputSources above.
  ++ inputSources;

  # Carry the config repo (flake + installer scripts) onto the ISO. The
  # installer auto-launches on the console (see below), but the tree also
  # stays reachable at /etc/nixos-config for a manual `./installer/install.sh`
  # rerun if the auto-run is aborted.
  environment.etc."nixos-config".source = self;
  # git for the repo clone; gptfdisk so install.sh's sgdisk partitioning runs
  # from the baked store instead of `nix shell nixpkgs#gptfdisk` (which would
  # hit the network and fail on this offline ISO).
  environment.systemPackages = [
    pkgs.git
    pkgs.gptfdisk
  ];

  # Bake the two live bootstrap secrets onto the ISO so the installer needs no
  # manual secret staging. Read impurely from the maintainer's local
  # out-of-store secrets dir at build time (the ISO build runs with --impure);
  # these paths are NOT in the flake tree, so nothing secret is committed. The
  # installer reads them via SECRETS_SOURCE_DIR=/etc/nixos-secrets (set below).
  # SECURITY: they land world-readable in the ISO's /nix/store, so this USB
  # carries cleartext credentials by design -- keep it private / wipe it after.
  environment.etc."nixos-secrets/mihomo-config.yaml".source =
    /home/andongni/.nixos-config/secrets/mihomo-config.yaml;
  environment.etc."nixos-secrets/credentials.json".source =
    /home/andongni/.nixos-config/secrets/hyprwhspr-credentials.json;

  # Auto-launch the installer on the console so booting the USB drops straight
  # into the install flow with no manual command typing. Root autologin on
  # tty1, then a login-shell hook runs installer/install.sh pointed at the
  # baked secrets. Guarded to tty1 (serial/other logins get a normal shell)
  # and to a once-per-session marker. The machine-identity prompts
  # (role/hostname/peerHost) and the disk-erase confirmation stay interactive.
  # `|| true` so an aborted or failed install drops to a usable shell.
  services.getty.autologinUser = lib.mkForce "root";
  environment.loginShellInit = ''
    if [[ "$(tty)" = /dev/tty1 && -z "''${_INSTALLER_LAUNCHED:-}" ]]; then
      export _INSTALLER_LAUNCHED=1
      export SECRETS_SOURCE_DIR=/etc/nixos-secrets
      bash /etc/nixos-config/installer/install.sh || true
    fi
  '';

  # Offline by design: fail loud instead of silently trying the network if
  # something isn't in the baked closure.
  nix.settings.substituters = lib.mkForce [ ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
