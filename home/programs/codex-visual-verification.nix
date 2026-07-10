{ config, pkgs, ... }:

let
  codexScreen = pkgs.callPackage ../../pkgs/codex-screen { };
  repository = "${config.home.homeDirectory}/Yandex.Disk/System/nixos-configuration";
in
{
  home.packages = [ codexScreen ];

  home.file.".codex/skills/visual-verification".source =
    config.lib.file.mkOutOfStoreSymlink "${repository}/skills/visual-verification";
}
