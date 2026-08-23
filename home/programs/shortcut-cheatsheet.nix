{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  # Sources for shortcut-cheatsheet-data.nix:
  #   Desktop/voice/hardware: dotfiles/hypr/hyprland.lua and the remote
  #     role fragment in home/programs/dotfiles.nix.
  #   Herdr: direct custom bindings in dotfiles/herdr/config.toml.
  #   Explain: the fork binding in dotfiles/herdr/config.toml plus the
  #     buffer-local maps and commands in dotfiles/nvim/lua/plugins/explain.lua
  #     and dotfiles/nvim/lua/plugins/readmode.lua.
  #   Yazi: dotfiles/yazi/keymap.toml plus the shipped built-in keymap.
  #   MPV: built-in input map; home/programs/mpv.nix leaves it unchanged.
  #   Shell: aliases and ZLE bindings in home/programs/shell.nix.
  # This is the compact daily-driver set, not an exhaustive list of the
  # defaults inherited from Hyprland, MPV, zsh, or Oh My Zsh.
  sections = import ./shortcut-cheatsheet-data.nix;

  # These are the only non-ASCII characters in the padded columns. Normalize
  # them before counting bytes so the visible separators stay aligned.
  visibleLength =
    value: builtins.stringLength (lib.replaceStrings [ "·" "–" "…" ] [ "." "-" "." ] value);
  padTo =
    width: value:
    let
      padding = lib.max 1 (width - visibleLength value);
    in
    value + lib.concatStrings (builtins.genList (_: " ") padding);
  escapeMarkup = lib.replaceStrings [ "&" "<" ">" ] [ "&amp;" "&lt;" "&gt;" ];
  renderRofiDisplay =
    section: binding:
    "<b>${escapeMarkup (padTo 22 section.name)}</b> │ "
    + "${escapeMarkup (padTo 26 binding.key)} │ "
    + escapeMarkup binding.description;
  renderRofiBinding = section: binding: ''
    ${pkgs.coreutils}/bin/printf '%s\0display\x1f%s\x1fmeta\x1f%s\n' \
      ${lib.escapeShellArg "${binding.key} ${binding.description}"} \
      ${lib.escapeShellArg (renderRofiDisplay section binding)} \
      ${lib.escapeShellArg section.name}
  '';
  rofiRows = lib.concatMapStrings (
    section: lib.concatMapStrings (renderRofiBinding section) section.bindings
  ) sections;

  shortcutCheatsheetData = pkgs.writeShellApplication {
    name = "shortcut-cheatsheet-data";
    text = ''
      if (( $# > 0 )); then
        exit 0
      fi

      ${pkgs.coreutils}/bin/printf '\0prompt\x1ffilter › \n'
      ${pkgs.coreutils}/bin/printf '\0markup-rows\x1ftrue\n'
      ${pkgs.coreutils}/bin/printf '\0no-custom\x1ftrue\n'
      ${rofiRows}
    '';
  };

  shortcutCheatsheet = pkgs.writeShellApplication {
    name = "shortcut-cheatsheet";
    text = ''
      exec ${pkgs.rofi}/bin/rofi \
        -show shortcuts \
        -modes ${lib.escapeShellArg "shortcuts:${shortcutCheatsheetData}/bin/shortcut-cheatsheet-data"} \
        -matching normal \
        -i \
        -no-sort \
        -theme ${lib.escapeShellArg "${config.xdg.configHome}/rofi/shortcut-cheatsheet.rasi"} \
        -kb-row-up ${lib.escapeShellArg "Up,Control+p,Alt+k"} \
        -kb-row-down ${lib.escapeShellArg "Down,Control+n,Alt+j"}
    '';
  };
in
{
  # The sheet describes the remote laptop's desktop and is deliberately absent
  # on the home role. The source inventory is curated rather than claiming to
  # be exhaustive: each section names the configuration it was read from.
  config = lib.mkIf (osConfig.portable.role == "remote") {
    home.packages = [ shortcutCheatsheet ];

    # Inherit the current Rofi phosphor theme while keeping the established
    # centered 1000x700 shortcut-reference footprint.
    xdg.configFile."rofi/shortcut-cheatsheet.rasi".text = ''
      @theme "current"

      * {
          font: "Hack Nerd Font 12";
      }

      window {
          width: 1000px;
          height: 700px;
          location: center;
          anchor: center;
      }

      listview {
          lines: 27;
          dynamic: false;
          scrollbar: true;
      }

      element {
          padding: 3px 6px;
      }

      entry {
          placeholder: "Search sections, keys, descriptions...";
      }
    '';

    # Super+R opens Rofi's drun mode, which discovers this canonical entry.
    xdg.dataFile."applications/shortcut-cheatsheet.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Shortcut Cheat Sheet
      GenericName=Keyboard and Alias Reference
      Comment=Search shortcut sections, keys, and descriptions
      Exec=${shortcutCheatsheet}/bin/shortcut-cheatsheet
      Icon=input-keyboard
      Terminal=false
      Categories=Utility;System;
      Keywords=shortcut;keybinding;hotkey;alias;herdr;yazi;mpv;hyprland;
      StartupNotify=false
    '';
  };
}
