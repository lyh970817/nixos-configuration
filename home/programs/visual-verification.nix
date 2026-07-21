{ config, pkgs, ... }:

let
  screenVerify = pkgs.callPackage ../../pkgs/screen-verify { };
in
{
  home.packages = [ screenVerify ];

  # All declared Claude profiles and Codex receive this skill through their
  # tracked configuration trees in mutable-configs.nix.
}
