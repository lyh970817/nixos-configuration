# Rofi Application Launcher Configuration
# Managed by home-manager
# Original: ~/.config/rofi/
# Theme switching handled by darkman hooks (symlinks to current.rasi)
{ config, pkgs, ... }:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;
in

{
  programs.rofi = {
    enable = true;
    package = pkgs.rofi; # rofi-wayland has been merged into rofi
    extraConfig = {
      modi = "drun,run,window";
      show-icons = false;
      display-drun = "Apps";
      display-run = "Run";
      display-window = "Windows";
    };
    theme = "current"; # References the symlink managed by darkman
  };

  # Theme files for darkman switching
  home.file = {
    ".config/rofi/themes/dark.rasi".text = ''
      * {
          bg: #${p.background};
          bg-alt: #${p.deepSurface};
          fg: #${p.foreground};
          fg-alt: #${p.secondaryText};
          border: #${p.foreground};
          # Selection fill. This carries background-coloured text, so it is one
          # rung above secondaryText: the green ladder's middle rungs sit at
          # 0.42-0.58x the luminance of their amber counterparts, and on
          # secondaryText the selected row measured 2.12:1 against its own
          # label. accent restores 4.94:1, closest to the 4.42:1 the amber
          # profile gave. Same substitution in foot, alacritty, btop, mako.
          selected: #${p.accent};
          background-color: transparent;
          text-color: @fg;
          font: "Hack Nerd Font 12";
      }

      window {
          width: 52em;
          background-color: @bg;
          border: 1px solid;
          border-color: @border;
          border-radius: 0;
          padding: 5px;
      }

      mainbox {
          background-color: transparent;
          children: [ inputbar, listview ];
      }

      inputbar {
          background-color: @bg;
          text-color: @fg;
          padding: 4px 5px;
          children: [ prompt, entry ];
          spacing: 10px;
      }

      prompt {
          text-color: @fg;
          background-color: transparent;
      }

      entry {
          text-color: @fg;
          background-color: transparent;
          placeholder: "Search...";
          placeholder-color: @fg-alt;
      }

      listview {
          background-color: @bg;
          columns: 1;
          lines: 6;
          cycle: true;
          dynamic: true;
          scrollbar: false;
      }

      element {
          background-color: @bg;
          text-color: @fg;
          border-radius: 0;
          padding: 3px 6px;
      }

      element.normal.normal {
          background-color: @bg;
          text-color: @fg;
      }

      element.selected.normal {
          background-color: @selected;
          text-color: @bg;
      }

      element.alternate.normal {
          background-color: @bg;
          text-color: @fg;
      }

      element selected {
          background-color: @selected;
          text-color: @bg;
          border: 1px solid;
          border-color: @border;
      }

      element-text {
          background-color: transparent;
          text-color: inherit;
      }

      scrollbar {
          handle-width: 6px;
          handle-color: @fg-alt;
          background-color: @bg-alt;
          border-radius: 0;
          margin: 0 0 0 5px;
      }

      message {
          background-color: @bg;
          border: 1px solid;
          border-color: @border;
          border-radius: 0;
          padding: 8px;
      }

      textbox {
          text-color: @fg;
          background-color: transparent;
      }
    '';

    ".config/rofi/themes/light.rasi".text = ''
      * {
          bg: #ffffff;
          bg-alt: #f5f5f5;
          fg: #000000;
          fg-alt: #555555;
          border: #000000;
          selected: #000000;
          background-color: transparent;
          text-color: @fg;
          font: "Hack Nerd Font 12";
      }

      window {
          background-color: @bg;
          border: 2px solid;
          border-color: @border;
          border-radius: 4px;
          padding: 5px;
      }

      mainbox {
          background-color: transparent;
          children: [ inputbar, listview ];
      }

      inputbar {
          background-color: @bg;
          text-color: @fg;
          padding: 4px 5px;
          children: [ prompt, entry ];
          spacing: 10px;
      }

      prompt {
          text-color: @fg;
          background-color: transparent;
      }

      entry {
          text-color: @fg;
          background-color: transparent;
          placeholder: "Search...";
          placeholder-color: @fg;
      }

      listview {
          background-color: @bg;
          columns: 1;
          lines: 6;
          cycle: true;
          dynamic: true;
          scrollbar: false;
      }

      element {
          background-color: @bg;
          text-color: @fg;
          border-radius: 2px;
          padding: 1px 5px;
      }

      element.normal.normal {
          background-color: @bg;
          text-color: @fg;
      }

      element.selected.normal {
          background-color: @fg;
          text-color: @bg;
      }

      element.alternate.normal {
          background-color: @bg;
          text-color: @fg;
      }

      element selected {
          background-color: @selected;
          text-color: @fg;
          border: 1px solid;
          border-color: @border;
      }

      element-text {
          background-color: transparent;
          text-color: inherit;
      }

      scrollbar {
          handle-width: 6px;
          handle-color: @fg-alt;
          background-color: @bg-alt;
          border-radius: 3px;
          margin: 0 0 0 5px;
      }

      message {
          background-color: @bg;
          border: 1px solid;
          border-color: @border;
          border-radius: 8px;
          padding: 10px;
      }

      textbox {
          text-color: @fg;
          background-color: transparent;
      }
    '';
  };
}
