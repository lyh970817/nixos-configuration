{ config, pkgs, ... }:

{
  # Core CLI utilities
  home.packages = with pkgs; [
    neovim
    wget
    git
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
    socat
    lsd
    starship
    tealdeer
    tmux
    yazi
    zoxide
    duf
    ncdu
    htop
    lazygit
    gh
  ];
}
