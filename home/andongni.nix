{ config, pkgs, ... }:

{
  # Configuration Management Strategy:
  # - Simple configs: Managed by home-manager (git, tmux, htop, starship, etc.)
  # - Theme-aware: Home-manager + darkman hooks (alacritty, rofi, mako, fzf)
  # - Complex/Active: Symlinked from ~/Yandex.Disk/System/nixos-configuration/dotfiles (nvim, yazi, hypr)
  # - Sensitive: Manual (ssh)

  imports = [
    ./programs/shell.nix
    ./programs/git.nix
    ./programs/ssh.nix
    ./programs/mpv.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    ./programs/htop.nix
    ./programs/alacritty.nix
    ./programs/mako.nix
    ./programs/rofi.nix
    ./programs/fzf.nix
    ./programs/r.nix
    ./programs/fastfetch.nix
    ./programs/claude.nix
    ./programs/gemini.nix
    ./programs/launchers.nix
    ./programs/dotfiles.nix
    ./desktop/theming.nix
    ./desktop/xdg.nix
    ./packages/base.nix
    ./packages/desktop.nix
    ./packages/development.nix
    ./packages/fonts.nix
  ];

  home.username = "andongni";
  home.homeDirectory = "/home/andongni";

  # Environment variables
  home.sessionVariables = {
    EDITOR = "nvim";
    TERMINAL = "alacritty";
    JAVA_HOME = "${pkgs.jdk17}/lib/openjdk";
    SSH_AUTH_SOCK = "$HOME/.bitwarden-ssh-agent.sock";
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  };

  home.sessionPath = [
    "$HOME/.npm-global/bin"
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # This value determines the Home Manager release
  home.stateVersion = "25.05";
}
