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

  shortcutCheatsheet = pkgs.writeShellApplication {
    name = "shortcut-cheatsheet";
    text = ''
      export CLICOLOR_FORCE=1
      exec ${keyb}/bin/keyb \
        --config ${lib.escapeShellArg "${config.xdg.configHome}/keyb/shortcut-cheatsheet.yml"} \
        --key ${lib.escapeShellArg "${config.xdg.configHome}/keyb/shortcuts.yml"}
    '';
  };
in
{
  # The sheet describes the remote laptop's desktop and is deliberately absent
  # on the home role. The source inventory below is curated rather than claiming
  # to be exhaustive: each section names the configuration it was read from.
  config = lib.mkIf (osConfig.portable.role == "remote") {
    home.packages = [ shortcutCheatsheet ];

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

      # Sources:
      #   Desktop/voice/hardware: dotfiles/hypr/hyprland.lua and the remote
      #     role fragment in home/programs/dotfiles.nix.
      #   Tmux: custom root/copy-mode bindings in home/programs/tmux.nix.
      #   Shell: aliases and ZLE bindings in home/programs/shell.nix.
      # This is the compact daily-driver set, not the defaults inherited from
      # Hyprland, tmux, zsh, or Oh My Zsh.
      "keyb/shortcuts.yml".text = ''
        - name: DESKTOP · LAUNCH
          keybinds:
            - name: Home session over SSH
              key: Super + Enter
            - name: Local Herdr session
              key: Super + Shift + Enter
            - name: Application launcher
              key: Super + R
            - name: Window switcher
              key: Super + Shift + R
            - name: Brave
              key: Super + W
            - name: Yazi in Foot
              key: Super + E
            - name: Thunar
              key: Super + Shift + E
            - name: Date and time
              key: Super + D

        - name: DESKTOP · WINDOWS
          keybinds:
            - name: Focus left / down / up / right
              key: Super + h / j / k / l
            - name: Move window left / down / up / right
              key: Super + Shift + h / j / k / l
            - name: Next / previous window
              key: Super + Tab / Super + Shift + Tab
            - name: Close / force close
              key: Super + q / Super + Shift + q
            - name: Toggle floating
              key: Super + s
            - name: Toggle fullscreen
              key: Super + f
            - name: Toggle pseudotile
              key: Super + p
            - name: Toggle split direction
              key: Super + v
            - name: Resize with arrows
              key: Super + Arrow keys
            - name: Drag / resize with mouse
              key: Super + left / right drag
            - name: Send window behind others
              key: Alt + Shift + b

        - name: DESKTOP · WORKSPACES
          keybinds:
            - name: Switch to workspace 1–10
              key: Super + 1…0
            - name: Move window to workspace 1–10
              key: Super + Shift + 1…0
            - name: Next / previous existing workspace
              key: Super + wheel down / up
            - name: Move window to workspace 10
              key: Super + m

        - name: DESKTOP · DISPLAY
          keybinds:
            - name: Toggle dark / light theme
              key: Super + Shift + t
            - name: Toggle night colour temperature
              key: Super + n
            - name: Full screenshot
              key: Print
            - name: Region screenshot
              key: Super + Shift + s
            - name: Restore laptop display after lid event
              key: Fn + F12

        - name: VOICE
          keybinds:
            - name: Toggle short dictation
              key: Super + o
            - name: Toggle long-form dictation
              key: Ctrl + Shift + l
            - name: Toggle dictation profile
              key: Ctrl + Shift + p
            - name: Cancel long-form dictation
              key: Super + Escape

        - name: LAPTOP · HARDWARE
          keybinds:
            - name: Cycle power profile
              key: Fn + F2
            - name: Toggle microphone mute
              key: Fn + F4
            - name: Brightness down / up
              key: Fn + F6 / F7
            - name: Toggle Mihomo proxy
              key: Fn + F8
            - name: Toggle touchpad
              key: Fn + F9
            - name: Cycle keyboard backlight
              key: Fn + Z
            - name: Cycle monitor scale
              key: Fn + Space
            - name: Volume mute / down / up
              key: Fn + Esc / 3 / 4
            - name: Microphone volume down / up
              key: Ctrl + Shift + d / u

        - name: TMUX · PANES
          keybinds:
            - name: Split horizontally
              key: Alt + Enter
            - name: Split vertically
              key: Shift + F10
            - name: Focus left / down / up / right
              key: Alt + h / j / k / l
            - name: Swap left / down / up / right
              key: Alt + Shift + h / j / k / l
            - name: Zoom pane
              key: Alt + f
            - name: Close pane
              key: Alt + q
            - name: New scratch note in horizontal split
              key: Ctrl + 1
            - name: New scratch note in vertical split
              key: Ctrl + Shift + 1

        - name: TMUX · WINDOWS
          keybinds:
            - name: Select or create window 1–10
              key: Alt + 1…0
            - name: Tmux command prefix
              key: Ctrl + a
            - name: Send Shift+Enter through to agent TUI
              key: Shift + Enter

        - name: TMUX · COPY MODE
          keybinds:
            - name: Enter copy mode
              key: Alt + v
            - name: Move cursor
              key: h / j / k / l
            - name: Start selection
              key: v
            - name: Copy selection to local clipboard
              key: y
            - name: Pick visible token with tmux-thumbs
              key: f
            - name: Page up / down
              key: Ctrl + b or u / Ctrl + d or f
            - name: Leave copy mode
              key: q

        - name: SHELL · KEYS
          keybinds:
            - name: Accept next suggested word
              key: Alt + f
            - name: Accept full suggestion
              key: Ctrl + f
            - name: Open Yazi and return in chosen directory
              key: Ctrl + o
            - name: Fuzzy command history
              key: Ctrl + r
            - name: Zeno completion
              key: Tab
            - name: Directory history back / forward
              key: Ctrl + Left / Right
            - name: Directory history up / down
              key: Ctrl + Up / Down

        - name: SHELL · CUSTOM ALIASES
          keybinds:
            - name: Ask Whai a natural-language question
              key: ","
            - name: Rebuild NixOS from /etc/nixos
              key: rebuild
            - name: Codex · unrestricted
              key: cdy
            - name: Codex orchestrator · unrestricted
              key: cdo
            - name: Claude · unrestricted
              key: cly
            - name: Opus 5 orchestrator · orchestrator-opus.md
              key: clo
            - name: Fable 5 orchestrator · orchestrator-fable.md
              key: clfo
            - name: Claude Matt Pocock profile
              key: claude-matt
            - name: Claude local GPT-5.6 gateway
              key: clg
            - name: Claude Matt profile · unrestricted
              key: clty
            - name: Claude GPT-5.6 gateway · unrestricted
              key: clgy
            - name: Git status
              key: gs
            - name: Git push
              key: gp
            - name: Git force push
              key: gpf
      '';
    };

    # Rofi's drun mode discovers this as “Shortcut Cheat Sheet”; the dedicated
    # wrapper fixes the declarative data/config paths and the existing
    # foot-float rule supplies the compact 1000x700 popup treatment.
    xdg.dataFile."applications/shortcut-cheatsheet.desktop".text = ''
      [Desktop Entry]
      Version=1.0
      Type=Application
      Name=Shortcut Cheat Sheet
      GenericName=Keyboard and Alias Reference
      Comment=Search configured desktop, tmux, shell, and alias shortcuts
      Exec=${pkgs.foot}/bin/foot --app-id foot-float --title "Shortcut Cheat Sheet" ${shortcutCheatsheet}/bin/shortcut-cheatsheet
      Icon=input-keyboard
      Terminal=false
      Categories=Utility;System;
      Keywords=shortcut;keybinding;hotkey;alias;tmux;hyprland;
      StartupNotify=false
    '';
  };
}
