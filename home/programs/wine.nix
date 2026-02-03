{ config, pkgs, lib, ... }:

{
  home.packages = with pkgs; [
    bottles
    winetricks
    cabextract
    steam-run
  ];
}
