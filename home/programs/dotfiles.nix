{ config, pkgs, ... }:

{
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "/home/andongni/nixos/dotfiles/nvim";
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "/home/andongni/nixos/dotfiles/hypr";
    "yazi".source = config.lib.file.mkOutOfStoreSymlink "/home/andongni/nixos/dotfiles/yazi";
  };
}
