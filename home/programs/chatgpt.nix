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
  home.packages = [
    pkgs.chatgpt
    pkgs.codex
  ];

  home.file.".codex-desktop/skills/herdr".source = link "dotfiles/universal-skills/herdr";
}
