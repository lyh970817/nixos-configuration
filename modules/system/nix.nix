{
  config,
  pkgs,
  lib,
  ...
}:

{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.trusted-users = [
    "root"
    "andongni"
  ];

  # Store upkeep. Retention is time-based rather than a generation count: at
  # ~6 rebuilds/day a count-based limit gives under two days of rollback.
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  # auto-optimise-store only dedups newly built paths; this sweeps the rest.
  nix.optimise.automatic = true;
}
