{
  lib,
  pkgs,
  ...
}:

# App dictation engines that run beside hyprwhspr; `dictation-engine`
# (scripts/dictation-engine) picks which one owns Super+O. Each app keeps its
# settings and sign-in in its own config directory, managed by the app itself.
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

  # A user service that runs only while its engine is selected; otherwise its
  # evdev trigger would fire alongside hyprwhspr on Super+O.
  appEngineService =
    {
      name,
      description,
      documentation,
      execStart,
      environment,
    }:
    {
      Unit = {
        Description = description;
        Documentation = documentation;
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
        ExecCondition = "${dictationEngine}/bin/dictation-engine is ${name}";
        ExecStart = execStart;
        Environment = environment;
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
in
{
  home.packages = [
    pkgs.doubao-say
    pkgs.wispr-flow
    dictationEngine
  ];

  systemd.user.services.doubao-say = appEngineService {
    name = "doubao-say";
    description = "Doubao Say voice input";
    documentation = "https://github.com/quanru/doubao-say";
    execStart = "${pkgs.doubao-say}/bin/doubao-say --background";
    environment = [
      # hyprctl: target-window checks and the temporary Escape lease.
      "PATH=${lib.makeBinPath [ pkgs.hyprland ]}"
      "PYTHONUNBUFFERED=1"
    ];
  };

  systemd.user.services.wispr-flow = appEngineService {
    name = "wispr-flow";
    description = "Wispr Flow voice dictation";
    documentation = "https://github.com/wispr-flow-linux/wispr-flow-linux";
    execStart = "${pkgs.wispr-flow}/bin/wispr-flow";
    environment = [
      # XWayland keeps its transparent status pill click-through on Hyprland
      # (upstream issues #44, #126).
      "WISPR_USE_X11=1"
    ];
  };
}
