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
}
