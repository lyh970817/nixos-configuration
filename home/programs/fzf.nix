# FZF Theme Files Configuration
# Managed by home-manager
# Original: ~/.config/fzf/themes/
# Both dark and light variants are written unconditionally by this file;
# shell.nix selects which one to use per-session based on THEME_MODE.
# Note: We don't use programs.fzf color options as they conflict with dynamic loading
{ config, pkgs, ... }:

{
  # Per-mode (dark/light) theme variant files, selected at shell startup by
  # THEME_MODE (set by theme-hold for ssh/mosh sessions, otherwise defaulted
  # from the local monitor)
  home.file = {
    ".config/fzf/themes/dark".text = ''
      --color=fg:#4AB34D
      --color=bg:#000000
      --color=hl:#3CA23F
      --color=fg+:#4AB34D
      --color=bg+:#045C07
      --color=hl+:#4AB34D
      --color=info:#2E9031
      --color=prompt:#4AB34D
      --color=pointer:#4AB34D
      --color=marker:#3CA23F
      --color=spinner:#2E9031
      --color=header:#207F23
      --color=border:#126D15
      --color=label:#3CA23F
      --color=query:#4AB34D
    '';

    ".config/fzf/themes/light".text = ''
      --color=info:#404040,prompt:#404040,pointer:#000000,marker:#000000
    '';
  };
}
