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
  # Keep terminal and Desktop CLI behavior aligned with Apps enabled.
  # Desktop still keeps GUI state out of ~/.codex.
  home.packages = [
    (pkgs.codex.override { disableApps = false; })
  ];

  home.file.".codex-desktop/skills/herdr".source = link "dotfiles/universal-skills/herdr";

  programs.codexDesktopLinux = {
    enable = true;
    package = pkgs.codex-desktop-isolated;
    # Desktop keeps Apps available in its own isolated Codex environment.
    cliPackage = pkgs.codex.override { disableApps = false; };
  };
}
