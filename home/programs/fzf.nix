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
      --color=fg:#D99B32
      --color=bg:#080705
      --color=hl:#BE842A
      --color=fg+:#D99B32
      --color=bg+:#0C0A06
      --color=hl+:#D99B32
      --color=info:#9B6D24
      --color=prompt:#D99B32
      --color=pointer:#D99B32
      --color=marker:#BE842A
      --color=spinner:#9B6D24
      --color=header:#6E501D
      --color=border:#2A2011
      --color=label:#BE842A
      --color=query:#D99B32
    '';

    ".config/fzf/themes/light".text = ''
      --color=info:#404040,prompt:#404040,pointer:#000000,marker:#000000
    '';
  };
}
