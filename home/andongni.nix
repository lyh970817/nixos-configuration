{ config, pkgs, ... }:

{
  # Configuration Management Strategy:
  # - Simple configs: Managed by home-manager (git, tmux, htop, starship, etc.)
  # - Theme-aware: Home-manager + darkman hooks (foot, rofi, mako, fzf)
  # - Complex/Active: Symlinked from ~/.nixos-config/dotfiles (nvim, yazi, hypr)
  # - Sensitive: Manual (ssh)

  imports = [
    ./programs/shell.nix
    ./programs/git.nix
    ./programs/ssh.nix
    ./programs/mpv.nix
    ./programs/gnome-keyring.nix
    ./programs/starship.nix
    ./programs/tmux.nix
    ./programs/htop.nix
    ./programs/btop.nix
    ./programs/foot.nix
    ./programs/mako.nix
    ./programs/rofi.nix
    ./programs/shortcut-cheatsheet.nix
    ./programs/fzf.nix
    ./programs/newt.nix
    ./programs/r.nix
    ./programs/fastfetch.nix
    ./programs/codexbar.nix
    ./programs/codex-theme.nix
    ./programs/claude.nix
    ./programs/cli-proxy-api.nix
    ./programs/codex-desktop.nix
    ./programs/claude-desktop.nix
    ./programs/visual-verification.nix
    ./programs/gemini.nix
    ./programs/herdr.nix
    ./programs/pi.nix
    ./programs/omp.nix
    ./programs/hyprwhspr.nix
    ./programs/quicktui.nix
    ./programs/launchers.nix
    ./programs/image-open.nix
    ./programs/html-open.nix
    ./programs/pre-commit.nix
    ./programs/qutebrowser.nix
    ./programs/nvim-theme.nix
    ./programs/yazi-theme.nix
    ./programs/dotfiles.nix
    ./programs/mutable-configs.nix
    ./directories.nix
    ./desktop/btop-workspace.nix
    ./desktop/mandala-wallpaper.nix
    ./desktop/theming.nix
    ./desktop/hyprsunset.nix
    ./desktop/phosphor-switch.nix
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
    TERMINAL = "foot";
    JAVA_HOME = "${pkgs.jdk17}/lib/openjdk";
    SSH_AUTH_SOCK = "$HOME/.bitwarden-ssh-agent.sock";
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    # Keep Go's module and build caches out of the home-directory root.
    GOMODCACHE = "$HOME/.cache/go/mod";
    GOCACHE = "$HOME/.cache/go/build";
    SCRATCH_DIR = "$HOME/.scratch";
    PI_NO_PTY = "1";
  };

  home.sessionPath = [
    "$HOME/.npm-global/bin"
    "$HOME/.local/bin"
  ];

  # Apply the same locations to Go invocations that do not inherit the shell
  # environment, such as installer subprocesses started by desktop apps.
  xdg.configFile."go/env".text = ''
    GOCACHE=${config.home.homeDirectory}/.cache/go/build
    GOMODCACHE=${config.home.homeDirectory}/.cache/go/mod
  '';

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # This value determines the Home Manager release
  home.stateVersion = "25.05";
}
