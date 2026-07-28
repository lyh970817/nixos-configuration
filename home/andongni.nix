{ config, pkgs, ... }:

{
  # Configuration Management Strategy:
  # - Simple configs: Managed by home-manager (git, tmux, htop, starship, etc.)
  # - Theme-aware: Home-manager + darkman hooks (alacritty, rofi, mako, fzf)
  # - Complex/Active: Symlinked from ~/.nixos-config/dotfiles (nvim, yazi, hypr)
  # - Sensitive: Manual (ssh)

  imports = [
    ./programs/shell.nix
    ./programs/git.nix
    ./programs/ssh.nix
    ./programs/mpv.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    ./programs/htop.nix
    ./programs/btop.nix
    ./programs/alacritty.nix
    ./programs/mako.nix
    ./programs/rofi.nix
    ./programs/fzf.nix
    ./programs/newt.nix
    ./programs/r.nix
    ./programs/fastfetch.nix
    ./programs/claude.nix
    ./programs/cli-proxy-api.nix
    ./programs/codex-desktop.nix
    ./programs/visual-verification.nix
    ./programs/gemini.nix
    ./programs/pi.nix
    ./programs/hyprwhspr.nix
    ./programs/quicktui.nix
    ./programs/launchers.nix
    ./programs/image-open.nix
    ./programs/dotfiles.nix
    ./programs/mutable-configs.nix
    ./directories.nix
    ./desktop/btop-workspace.nix
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
    SCRATCH_DIR = "$HOME/.scratch";
  };

  home.sessionPath = [
    "$HOME/.npm-global/bin"
  ];

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # This value determines the Home Manager release
  home.stateVersion = "25.05";
}
