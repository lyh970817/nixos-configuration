{
  pkgs,
  ...
}:

{
  # The terminal CLI and Desktop run independently: Desktop owns bundled
  # node_repl while its launcher keeps GUI state out of ~/.codex.
  home.packages = [ pkgs.codex ];

  programs.codexDesktopLinux = {
    enable = true;
    package = pkgs.codex-desktop-isolated;
    cliPackage = null;
  };
}
