{ config, pkgs, ... }:

{
  # Font packages
  home.packages = with pkgs; [
    glasstty-ttf
    nerd-fonts.hack
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    wqy_zenhei
    source-han-sans
    source-han-serif
  ];
}
