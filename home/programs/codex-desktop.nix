{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";

in
{
  # Keep Apps out of the terminal CLI; Desktop enables them in its isolated state.
  home.packages = [
    pkgs.codex
  ];

  home.file.".codex-desktop/skills/herdr".source = link "dotfiles/universal-skills/herdr";

  programs.codexDesktopLinux = {
    enable = true;
    package = pkgs.codex-desktop-isolated;
    # Desktop keeps Apps available in its own isolated Codex environment.
    cliPackage = pkgs.codex.override { disableApps = false; };
  };
}
