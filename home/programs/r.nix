# R Language Configuration
# Managed by home-manager
# Original: ~/.Renviron
{ config, pkgs, ... }:

{
  home.file = {
    ".Renviron".text = ''
      R_LIBS_USER=~/.local/share/R/library/%v
    '';
  };
}
