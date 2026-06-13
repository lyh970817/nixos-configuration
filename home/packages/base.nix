{ config, pkgs, ... }:

{
  # Core CLI utilities
  home.packages = with pkgs; [
    neovim
    wget
    file
    tree
    unzip
    zip
    wl-clipboard
    grim
    slurp
    ripgrep
    fd
    bat
    fzf
    jq
    lsd
    tealdeer
    yazi
    duf
    ncdu
    lazygit
  ];
}
