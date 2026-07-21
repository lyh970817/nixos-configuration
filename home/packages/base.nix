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
    # Editor essentials on every role: gcc for nvim-treesitter parser
    # compilation; nil + nixfmt for editing this Nix config on the remote too.
    gcc
    nil
    nixfmt
  ];
}
