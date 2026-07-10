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
        Requires = [ "btop-workspace-guard.service" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.alacritty}/bin/alacritty --class Alacritty-btop --title btop-dashboard --command %h/.config/hypr/scripts/btop-dashboard.sh";
        Restart = "always";
        RestartSec = "1s";
        StandardOutput = "journal";
        StandardError = "journal";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
