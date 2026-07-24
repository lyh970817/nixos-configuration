{ lib, ... }:

{
  # Per-machine anchor for out-of-tree, git-ignored bootstrap secrets. Set at
  # install time in the generated /etc/nixos/local.nix. Both the system proxy
  # secret and the user dictation credential are read (as absolute-path strings,
  # never copied into the world-readable store) from <configDir>/secrets/.
  options.portable.configDir = lib.mkOption {
    type = lib.types.str;
    default = "/etc/nixos";
    example = "/home/andongni/.nixos-config";
    description = ''
      Absolute path to this machine's checked-out configuration repository.
      Bootstrap secrets live in <configDir>/secrets/ (git-ignored) and are read
      by absolute path at runtime/activation, so they stay out of git and the
      Nix store. Home-Manager modules read the same value via osConfig.
    '';
  };

  # home = full workstation you SSH into; remote = portable laptop that
  # connects to home over Tailscale.
  options.portable.role = lib.mkOption {
    type = lib.types.enum [
      "home"
      "remote"
    ];
    default = "home";
    description = ''
      Which side of the two-machine setup this host is. Determines
      home-vs-remote-only behavior elsewhere in the configuration.
    '';
  };

  # Tailscale/MagicDNS name of the *other* machine (home sets this to the
  # remote's name, remote sets it to "home"). Used for silent cross-machine
  # theme sync and for the remote's `mosh home` terminal. Empty string means
  # "no peer / disable cross-machine features".
  options.portable.peerHost = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = ''
      Tailscale/MagicDNS hostname of the peer machine in the home/remote
      pair. Left empty to disable cross-machine features.
    '';
  };

  # Opt-in, per-machine hardware workarounds. Not implied by role, since
  # role is shared by any host on that side of the pair, not by this quirk.
  options.portable.quirks.dynabookX30wkDmic = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enables the DMIC quirk for the Dynabook PORTEGE X30W-K, whose NHLT
      table under-reports 2 DMICs instead of 4, leaving the internal mic
      silent.
    '';
  };

  options.portable.quirks.dynabookX30wkHotkeys = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enables the Fn hotkey quirk for the Dynabook PORTEGE X30W-K, whose
      firmware only emits ACPI brightness events for Fn+F6/F7 after mailbox
      flags are set that Windows vendor software normally sets. Loads a
      custom SSDT and arms the flags via acpi_call at boot and resume.
    '';
  };

  options.portable.quirks.arb33pThermalCap = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enables the ryzenadj thermal/power envelope for the ARB33P board (AMD
      Ryzen 7 8840U, amd-pstate-epp), which otherwise runs unmanaged up to
      the 105/110C ACPI trip points. Loads the ryzen_smu kernel module for
      SMU access and applies a ryzenadj oneshot + timer that keeps boost
      usable for bursts while capping sustained STAPM/slow/fast power limits
      and the Tctl target.
    '';
  };
}
