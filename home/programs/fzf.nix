# FZF Theme Files Configuration
# Managed by home-manager
# Original: ~/.config/fzf/themes/
# Both dark and light variants are written unconditionally by this file;
# shell.nix selects which one to use per-session based on THEME_MODE.
# Note: We don't use programs.fzf color options as they conflict with dynamic loading
{ config, pkgs, ... }:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;
in

{
  # Per-mode (dark/light) theme variant files, selected at shell startup by
  # THEME_MODE (set by theme-hold for ssh/mosh sessions, otherwise defaulted
  # from the local monitor)
  home.file = {
    ".config/fzf/themes/dark".text = ''
      --color=fg:#${p.foreground}
      --color=bg:#${p.background}
      --color=hl:#${p.accent}
      --color=fg+:#${p.foreground}
      --color=bg+:#${p.deepSurface}
      --color=hl+:#${p.foreground}
      --color=info:#${p.secondaryText}
      --color=prompt:#${p.foreground}
      --color=pointer:#${p.foreground}
      --color=marker:#${p.accent}
      --color=spinner:#${p.secondaryText}
      --color=header:#${p.mutedText}
      --color=border:#${p.subtleBorder}
      --color=label:#${p.accent}
      --color=query:#${p.foreground}
    '';

    ".config/fzf/themes/light".text = ''
      --color=info:#404040,prompt:#404040,pointer:#000000,marker:#000000
    '';
  };
}
