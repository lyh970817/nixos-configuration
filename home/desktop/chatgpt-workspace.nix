{ pkgs, ... }:

{
  # ChatGPT Desktop starts with the graphical session and lands on workspace 9
  # (the `chatgpt-workspace-9` window rule in dotfiles/hypr/hyprland.lua). The
  # rule only applies at map time, so the window stays movable afterwards.
  #
  # Restart is deliberately `on-failure`, not `always`: Super+Shift+Q
  # (forcekillactive -> SIGKILL) is a unit failure and brings the app back on
  # workspace 9, while Super+Q (killactive -> a clean close) exits 0 and leaves
  # it down until the user launches it again.
  systemd.user.services.chatgpt = {
    Unit = {
      Description = "ChatGPT Desktop";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.chatgpt}/bin/chatgpt --class=chatgpt";
      Restart = "on-failure";
      RestartSec = "2s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
