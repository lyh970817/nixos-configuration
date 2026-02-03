{ config, pkgs, ... }:

{
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "/home/andongni/nixos-configuration/dotfiles/nvim";
    "hypr".source = config.lib.file.mkOutOfStoreSymlink "/home/andongni/nixos-configuration/dotfiles/hypr";
    "yazi".source = config.lib.file.mkOutOfStoreSymlink "/home/andongni/nixos-configuration/dotfiles/yazi";
  };
}
