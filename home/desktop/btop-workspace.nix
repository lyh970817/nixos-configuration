{ pkgs, ... }:

let
  btopWorkspace = pkgs.writeShellApplication {
    name = "btop-workspace";
    runtimeInputs = with pkgs; [
      coreutils
      hyprland
      jq
      libnotify
      socat
      systemd
    ];
    text = builtins.readFile ../../dotfiles/hypr/scripts/btop-workspace.sh;
  };
in
{
  home.packages = [ btopWorkspace ];

  systemd.user.targets.hyprland-session.Unit = {
    Description = "Hyprland graphical session";
    BindsTo = [ "graphical-session.target" ];
    Wants = [ "graphical-session-pre.target" ];
    After = [ "graphical-session-pre.target" ];
    Before = [ "graphical-session.target" ];
  };

  systemd.user.services = {
    btop-workspace-guard = {
      Unit = {
        Description = "Keep Hyprland workspace 10 exclusive to the btop dashboard";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${btopWorkspace}/bin/btop-workspace daemon";
        Restart = "always";
        RestartSec = "1s";
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    btop-dashboard = {
      Unit = {
        Description = "Managed btop dashboard on Hyprland workspace 10";
        PartOf = [ "graphical-session.target" ];
        After = [
          "btop-workspace-guard.service"
          "graphical-session.target"
        ];
        # Wants, deliberately not Requires. Home Manager switches these units
        # with sd-switch, which stops and starts only the units whose own
        # definition changed. A rebuild that changes the guard's closure but
        # not the dashboard's -- a nixpkgs bump touching coreutils, hyprland,
        # jq, libnotify, socat or systemd, none of which the dashboard is built
        # from -- puts the guard alone on that list. Under Requires= systemd
        # took the dashboard down with the guard's stop job as an ordered
        # casualty, and sd-switch then started back only the guard, so the pane
        # stayed dead until it was started by hand. Restart=always does not
        # cover that (a deliberate stop is not a crash) and neither does
        # PartOf=graphical-session.target (the target itself never cycled).
        #
        # Wants= keeps both directions that were actually wanted -- starting
        # the dashboard still pulls the guard in, and After= still orders it
        # behind the guard -- and drops only the stop propagation, which is the
        # bug. Nothing is lost, because the dashboard does not need the guard to
        # come up: the pane is put on workspace 10 and made fullscreen by the
        # btop-dashboard window rule in hyprland.lua and by the script's own
        # focus block. The guard only enforces exclusivity afterwards, so a
        # dashboard running briefly unguarded is a workspace 10 that other
        # windows can be moved onto, not a broken dashboard. The guard's own
        # Restart=always brings it back within the second, and its startup
        # reconcile re-adopts the still-running pane by matching the window's
        # PID against this service's MainPID.
        Wants = [ "btop-workspace-guard.service" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.kitty}/bin/kitty --class kitty-btop --title btop-dashboard %h/.config/hypr/scripts/btop-dashboard.sh";
        Restart = "always";
        RestartSec = "1s";
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
