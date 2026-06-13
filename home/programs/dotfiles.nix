{ config, pkgs, ... }:

{
  xdg.configFile = {
    "nvim".source = ../../dotfiles/nvim;
    "hypr".source = ../../dotfiles/hypr;
    "yazi".source = ../../dotfiles/yazi;
    "znt".source = ../../dotfiles/znt;
  };
}
