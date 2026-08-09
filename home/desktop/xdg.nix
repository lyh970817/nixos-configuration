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

  # The mime associations above only cover schemes that are registered. Handed a
  # URL whose scheme has no handler -- `about:blank`, which CLIProxyAPI's codex
  # login probes with before it opens the real auth URL -- xdg-open falls back to
  # a hardcoded list that starts `x-www-browser:firefox:...`, and firefox is what
  # answers. $BROWSER is consulted before that list, so declaring it here is what
  # keeps the fallback path on brave too. An absolute path, not a bare name: the
  # point of this variable is to be usable from processes that do not carry the
  # user profile on PATH.
  home.sessionVariables.BROWSER = "${pkgs.brave}/bin/brave";
}
