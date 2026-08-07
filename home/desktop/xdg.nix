{ config, pkgs, ... }:

{
  xdg.enable = true;

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
      # brave-browser.desktop, not com.brave.Browser.desktop: the latter is the
      # upstream duplicate that home/programs/launchers.nix hides.
      "text/html" = "brave-browser.desktop";
      "application/xhtml+xml" = "brave-browser.desktop";
      "x-scheme-handler/http" = "brave-browser.desktop";
      "x-scheme-handler/https" = "brave-browser.desktop";
      "x-scheme-handler/mailto" = "brave-browser.desktop";
    };
  };
}
