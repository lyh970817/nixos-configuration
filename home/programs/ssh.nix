{ config, pkgs, ... }:

{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "create" = {
        hostname = "hpc.create.kcl.ac.uk";
        user = "k1764630";
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };
}
