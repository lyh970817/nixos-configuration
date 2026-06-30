{ lib, pkgs, ... }:

let
  runtimePath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.dbus
    pkgs.ffmpeg
    pkgs.glib
    pkgs.gnugrep
    pkgs.gnused
    pkgs.hyprland
    pkgs.libnotify
    pkgs.pipewire
    pkgs.pulseaudio
    pkgs.which
    pkgs.wl-clipboard
    pkgs.wtype
    pkgs.ydotool
  ];
in
{
  home.packages = [ pkgs.hyprwhspr ];

  xdg.configFile = {
    "hyprwhspr/config.rest-template.json".text = builtins.toJSON {
      "$schema" = "https://raw.githubusercontent.com/goodroot/hyprwhspr/main/share/config.schema.json";
      transcription_backend = "rest-api";
      rest_api_provider = "custom";
      rest_endpoint_url = "https://YOUR-ENDPOINT/v1/audio/transcriptions";
      rest_body = {
        model = "YOUR_MODEL";
      };
      rest_timeout = 30;
      rest_audio_format = "wav";
      recording_mode = "toggle";
      use_hypr_bindings = true;
      primary_shortcut = "CTRL+SHIFT+O";
      cancel_shortcut = "SUPER+ESCAPE";
    };

    "hyprwhspr/README-nixos-rest.md".text = ''
      # hyprwhspr REST setup

      This file is managed by Home Manager as a non-secret setup note.

      Live user-owned files:

      - `~/.config/hyprwhspr/config.json`
      - `~/.local/share/hyprwhspr/credentials`

      Start from the template:

      ```sh
      mkdir -p ~/.config/hyprwhspr ~/.local/share/hyprwhspr
      cp ~/.config/hyprwhspr/config.rest-template.json ~/.config/hyprwhspr/config.json
      chmod 700 ~/.config/hyprwhspr ~/.local/share/hyprwhspr
      nvim ~/.config/hyprwhspr/config.json
      ```

      Put the custom provider API key in the credential store:

      ```sh
      printf '{\n  "custom": "YOUR_API_KEY"\n}\n' > ~/.local/share/hyprwhspr/credentials
      chmod 600 ~/.local/share/hyprwhspr/credentials
      ```

      Then restart and validate:

      ```sh
      systemctl --user restart hyprwhspr.service
      hyprwhspr validate
      hyprwhspr status
      ```
    '';
  };

  systemd.user.services.hyprwhspr = {
    Unit = {
      Description = "hyprwhspr speech-to-text";
      Documentation = "https://github.com/goodroot/hyprwhspr";
      ConditionPathExists = [
        "%h/.config/hyprwhspr/config.json"
        "%h/.local/share/hyprwhspr/credentials"
      ];
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "pipewire.service"
        "wireplumber.service"
      ];
      Wants = [
        "pipewire.service"
        "wireplumber.service"
      ];
    };

    Service = {
      Type = "simple";
      ExecStartPre = "${pkgs.bash}/bin/bash -lc 'for i in $(${pkgs.coreutils}/bin/seq 1 60); do ${pkgs.coreutils}/bin/ls \"$XDG_RUNTIME_DIR\"/wayland-* >/dev/null 2>&1 && exit 0; ${pkgs.coreutils}/bin/sleep 0.25; done; echo \"Wayland socket not found\"; exit 1'";
      ExecStart = "${pkgs.hyprwhspr}/bin/hyprwhspr";
      ExecStopPost = "${pkgs.bash}/bin/bash -c '(${pkgs.procps}/bin/pkill -9 -f \"hyprwhspr-virtual-keyboard\" 2>/dev/null; ${pkgs.procps}/bin/pkill -9 -f \"hyprwhspr-ydotool.sock\" 2>/dev/null) || true'";
      Environment = [
        "HYPRWHSPR_ROOT=${pkgs.hyprwhspr}/lib/hyprwhspr"
        "PATH=${runtimePath}"
        "PYTHONUNBUFFERED=1"
      ];
      Restart = "on-failure";
      RestartSec = "2s";
      StandardOutput = "journal";
      StandardError = "journal";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
