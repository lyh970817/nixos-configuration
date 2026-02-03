{ config, pkgs, ... }:

{
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "application/pdf" = "sioyek.desktop";
      "text/plain" = "nvim.desktop";
      "x-scheme-handler/teams" = "teams-for-linux.desktop";
      "x-scheme-handler/mailto" = "brave-browser.desktop";
    };
  };
}
