{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  p = (import ../palettes.nix).active;
  keyb = pkgs.callPackage ../../pkgs/keyb.nix { };
  sections = import ./shortcut-cheatsheet-data.nix;

  renderKeybBinding =
    binding:
    "    - name: ${builtins.toJSON binding.description}\n"
    + "      key: ${builtins.toJSON binding.key}\n";
  renderKeybSection =
    section:
    "- name: ${builtins.toJSON section.name}\n"
    + "  keybinds:\n"
    + lib.concatMapStrings renderKeybBinding section.bindings;
  keybData = lib.concatMapStringsSep "\n" renderKeybSection sections;

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
    "<b>${escapeMarkup (padTo 24 section.name)}</b> │ "
    + "${escapeMarkup (padTo 38 binding.key)} │ "
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

  shortcutCheatsheet = pkgs.writeShellApplication {
    name = "shortcut-cheatsheet";
    text = ''
      export CLICOLOR_FORCE=1
      exec ${keyb}/bin/keyb \
        --config ${lib.escapeShellArg "${config.xdg.configHome}/keyb/shortcut-cheatsheet.yml"} \
        --key ${lib.escapeShellArg "${config.xdg.configHome}/keyb/shortcuts.yml"}
    '';
  };

  rofiCheatsheetData = pkgs.writeShellApplication {
    name = "shortcut-cheatsheet-rofi-data";
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

  rofiCheatsheet = pkgs.writeShellApplication {
    name = "shortcut-cheatsheet-rofi";
    text = ''
      exec ${pkgs.rofi}/bin/rofi \
        -show shortcuts \
        -modes ${lib.escapeShellArg "shortcuts:${rofiCheatsheetData}/bin/shortcut-cheatsheet-rofi-data"} \
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
    home.packages = [
      shortcutCheatsheet
      rofiCheatsheet
    ];

    xdg.configFile = {
      "keyb/shortcut-cheatsheet.yml".text = ''
        settings:
          keyb_path: ${config.xdg.configHome}/keyb/shortcuts.yml
          reverse: true
          mouse: true
          search_mode: false
          sort_keys: false
          title: " SHORTCUTS · REMOTE "
          prompt: "filter › "
          prompt_location: bottom
          placeholder: "type to search every section"
          prefix_sep: "+"
          sep_width: 5
          margin: 1
          padding: 1
          border: rounded
        color:
          prompt: "#${p.foreground}"
          cursor_fg: "#${p.background}"
          cursor_bg: "#${p.accent}"
          filter_fg: "#${p.hot}"
          counter_fg: "#${p.secondaryText}"
          placeholder_fg: "#${p.mutedText}"
          border_color: "#${p.foreground}"
      '';

      # Sources for shortcut-cheatsheet-data.nix:
      #   Desktop/voice/hardware: dotfiles/hypr/hyprland.lua and the remote
      #     role fragment in home/programs/dotfiles.nix.
      #   Herdr: direct custom bindings in dotfiles/herdr/config.toml.
      #   MPV: built-in input map; home/programs/mpv.nix leaves it unchanged.
      #   Shell: aliases and ZLE bindings in home/programs/shell.nix.
      # This is the compact daily-driver set, not an exhaustive list of the
      # defaults inherited from Hyprland, MPV, zsh, or Oh My Zsh.
      "keyb/shortcuts.yml".text = keybData;

      # The comparison sheet inherits the current Rofi phosphor theme while
      # matching the keyb popup's 1000x700 centered footprint.
      "rofi/shortcut-cheatsheet.rasi".text = ''
        @theme "current"

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
    };

    # Rofi's drun mode discovers both comparison entries. The original keyb
    # launcher and its Foot-hosted treatment remain unchanged.
    xdg.dataFile = {
      "applications/shortcut-cheatsheet.desktop".text = ''
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=Shortcut Cheat Sheet
        GenericName=Keyboard and Alias Reference
        Comment=Search configured desktop, Herdr, MPV, shell, and alias shortcuts
        Exec=${pkgs.foot}/bin/foot --app-id foot-float --title "Shortcut Cheat Sheet" ${shortcutCheatsheet}/bin/shortcut-cheatsheet
        Icon=input-keyboard
        Terminal=false
        Categories=Utility;System;
        Keywords=shortcut;keybinding;hotkey;alias;herdr;mpv;hyprland;
        StartupNotify=false
      '';

      "applications/shortcut-cheatsheet-rofi.desktop".text = ''
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=Shortcut Cheat Sheet (Rofi)
        GenericName=Keyboard and Alias Reference
        Comment=Compare the Rofi-backed searchable shortcut reference
        Exec=${rofiCheatsheet}/bin/shortcut-cheatsheet-rofi
        Icon=input-keyboard
        Terminal=false
        Categories=Utility;System;
        Keywords=shortcut;keybinding;hotkey;alias;herdr;mpv;hyprland;rofi;comparison;
        StartupNotify=false
      '';
    };
  };
}
