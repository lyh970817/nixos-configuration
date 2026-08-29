# R Language Configuration
# Managed by home-manager
# Original: ~/.Renviron
{ config, pkgs, ... }:

{
  home.file = {
    ".Renviron".text = ''
      R_LIBS_USER=${config.xdg.dataHome}/R/library/%v
    '';
  };
}
