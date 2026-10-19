{
  lib,
  pkgs,
  ...
}:

# doubao-say runs beside hyprwhspr as an alternative short-dictation engine;
# `dictation-engine` (scripts/dictation-engine) picks which one owns Super+O.
# Its settings, Doubao sign-in and history live in ~/.config/doubao-say and are
# managed by the app itself.
let
  dictationEngine = pkgs.writeShellApplication {
    name = "dictation-engine";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      pkgs.systemd
      pkgs.util-linux
    ];
    text = builtins.readFile ../../scripts/dictation-engine;
  };
in
{
  home.packages = [
    pkgs.doubao-say
    dictationEngine
  ];

  systemd.user.services.doubao-say = {
    Unit = {
      Description = "Doubao Say voice input";
      Documentation = "https://github.com/quanru/doubao-say";
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
      # Runs only while it is the selected engine; otherwise its evdev trigger
      # would fire alongside hyprwhspr on Super+O.
      ExecCondition = "${dictationEngine}/bin/dictation-engine is-doubao-say";
      ExecStart = "${pkgs.doubao-say}/bin/doubao-say --background";
      # hyprctl: target-window checks and the temporary Escape lease.
      Environment = [
        "PATH=${lib.makeBinPath [ pkgs.hyprland ]}"
        "PYTHONUNBUFFERED=1"
      ];
      Restart = "on-failure";
      RestartSec = "2s";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
