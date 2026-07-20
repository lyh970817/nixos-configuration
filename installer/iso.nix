# installer/iso.nix
#
# Configuration for the self-contained installer ISO (issue 07). Layered on
# top of nixpkgs' minimal installation-cd module (wired in flake.nix's
# `nixosConfigurations.installer`). Bakes a representative target closure --
# the actual `system` output's toplevel, plus both vendors' CPU microcode,
# plus the flake input source trees -- into the ISO's own Nix store, so
# `nixos-install` on the target builds/fetches almost nothing. The few
# target-specific paths that DO differ (e.g. the laptop's own initrd) are
# fetched through a mihomo proxy the installer brings up over Wi-Fi
# (net-up.sh), so the install never dies on a missing dep. Also carries the
# whole git-tracked repo (flake + installer scripts) onto the ISO so
# `installer/install.sh` can run straight from the booted environment.
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
  # direct and transitive, so the target machine can EVALUATE #system without
  # touching GitHub (which is blocked behind the GFW even with the proxy up).
  # targetToplevel only bakes the config's runtime *closure*; the eval itself
  # still needs the nixpkgs/home-manager/... source trees, which are not
  # runtime deps and would otherwise be fetched. The graph is a finite DAG
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
  # from the baked store instead of `nix shell nixpkgs#gptfdisk`. mihomo +
  # yq-go + curl drive the Wi-Fi/proxy bootstrap (net-up.sh): mihomo replays
  # the baked config to give the installer full proxied internet, so anything
  # not baked (e.g. the target's own initrd) is fetched through the user's
  # tunnel instead of failing. networkmanager provides nmtui for Wi-Fi.
  environment.systemPackages = [
    pkgs.git
    pkgs.gptfdisk
    pkgs.mihomo
    pkgs.yq-go
    pkgs.curl
    pkgs.networkmanager
  ];

  # Wi-Fi bring-up in the installer (the target is Wi-Fi only). NetworkManager
  # gives nmtui, an interactive SSID+password picker; force off the base ISO's
  # standalone wpa_supplicant so the two don't fight over the interface.
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;

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

  # Also bake this machine's live mihomo working state (resolved node list,
  # selected-node cache, rulesets, geoip db -- ~13MB). net-up.sh drops it into
  # mihomo's data dir so the installer's mihomo boots straight from the cached
  # nodes and connects directly (the nodes ARE reachable in-country) instead of
  # depending on the subscription/ruleset/geoip URLs being reachable on bare
  # Wi-Fi before the tunnel exists. Also preserves the currently-selected node.
  environment.etc."nixos-secrets/mihomo-cache".source =
    /home/andongni/.nixos-config/secrets/mihomo-cache;

  # Auto-launch the installer on the console so booting the USB drops straight
  # into the install flow with no manual command typing. Root autologin on
  # tty1, then a login-shell hook runs net-up.sh (Wi-Fi + mihomo proxy) and,
  # once egress works, installer/install.sh. net-up.sh writes the proxy env to
  # /run/installer-proxy-env, which we source so nixos-install inherits it.
  # Guarded to tty1 (serial/other logins get a normal shell) and to a
  # once-per-session marker. The machine-identity prompts (role/hostname/
  # peerHost) and the disk-erase confirmation stay interactive. `|| true` so an
  # aborted or failed step drops to a usable shell instead of logging out.
  services.getty.autologinUser = lib.mkForce "root";
  environment.loginShellInit = ''
    if [[ "$(tty)" = /dev/tty1 && -z "''${_INSTALLER_LAUNCHED:-}" ]]; then
      export _INSTALLER_LAUNCHED=1
      bash /etc/nixos-config/installer/net-up.sh || true
      [[ -f /run/installer-proxy-env ]] && . /run/installer-proxy-env
      export SECRETS_SOURCE_DIR=/etc/nixos-secrets
      bash /etc/nixos-config/installer/install.sh || true
    fi
  '';

  # Fast path is still the baked closure (nixos-install builds/fetches almost
  # nothing); the public cache is kept ONLY as a fallback for the handful of
  # target-specific paths (e.g. the laptop's own initrd), reached through the
  # mihomo proxy net-up.sh brings up. Not forced empty anymore -- see net-up.sh
  # / the nix-daemon proxy drop-in it installs.
  nix.settings.substituters = lib.mkForce [ "https://cache.nixos.org" ];
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
