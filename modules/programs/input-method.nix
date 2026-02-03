{ config, pkgs, lib, ... }:

{
  # Fcitx5 input method configuration
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [
      qt6Packages.fcitx5-chinese-addons
      fcitx5-gtk
      fcitx5-pinyin-zhwiki
      fcitx5-lua
    ];
  };

  # Force GTK_IM_MODULE to be empty (required for some applications)
  environment.variables.GTK_IM_MODULE = lib.mkForce "";
}
