{
  pkgs,
  lib,
  osConfig,
  ...
}:

{
  # Coding CLI: pkgs.codex on both roles. Desktop tray integration stays
  # home role only, pointed at the same package (cliPackage only feeds the
  # tray's CODEX_CLI_PATH wrapper, not PATH, so this doesn't double-install).
  config = {
    home.packages = [ pkgs.codex ];
  }
  // lib.optionalAttrs (osConfig.portable.role == "home") {
    programs.codexDesktopLinux = {
      enable = true;
      cliPackage = pkgs.codex;
    };
  };
}
