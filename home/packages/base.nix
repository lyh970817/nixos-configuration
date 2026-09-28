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
    deno
    jq
    tealdeer
    yazi
    # Yazi's image-preview fallback (Unicode blocks) when no graphics protocol
    # reaches the terminal, as in the laptop's mosh session to home.
    chafa
    duf
    ncdu
    lazygit
    # Editor essentials on every role: gcc for nvim-treesitter parser
    # compilation; nil + nixfmt for editing this Nix config on the remote too.
    gcc
    nil
    nixfmt
    # Shared user-space Node.js for npm tooling on both roles.
    nodejs_latest
  ];
}
