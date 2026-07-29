{
  pkgs,
  ...
}:

{
  # Keep terminal Apps disabled without changing the CLI Desktop launches.
  # The Desktop launcher also keeps GUI state out of ~/.codex.
  home.packages = [ pkgs.codex ];

  programs.codexDesktopLinux = {
    enable = true;
    package = pkgs.codex-desktop-isolated;
    cliPackage = pkgs.codex-desktop-cli;
  };
}
