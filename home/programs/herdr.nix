{ pkgs, ... }:

{
  # Terminal agent multiplexer; useful on both roles, so it is not gated on
  # `portable.role`. The package comes from the pinned upstream flake input
  # via the overlay in flake.nix.
  home.packages = [ pkgs.herdr ];

  # "Zero chrome" layout: sidebar hidden, tab bar hidden while a single tab is
  # open, no pane borders or gaps.
  #
  # `theme.name = "terminal"` selects the one built-in palette that emits plain
  # ANSI slots instead of hardcoded RGB, so herdr inherits whatever palette
  # Alacritty is currently importing and follows `theme-toggle` between dark and
  # light for free. This repo has no shared palette to reference; see
  # home/programs/alacritty.nix for the two ANSI palettes and
  # home/desktop/theming.nix for the switch.
  xdg.configFile."herdr/config.toml".text = ''
    [theme]
    name = "terminal"

    [ui]
    sidebar_start_collapsed = true
    sidebar_collapsed_mode = "hidden"
    hide_tab_bar_when_single_tab = true
    pane_borders = false
    pane_gaps = false
    accent = "green"
  '';
}
