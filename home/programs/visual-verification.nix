{ config, pkgs, ... }:

let
  screenVerify = pkgs.callPackage ../../pkgs/screen-verify { };
in
{
  home.packages = [ screenVerify ];

  # All declared Claude profiles, Codex, and OMP receive this skill through
  # their tracked configuration trees.
}
