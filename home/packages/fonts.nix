{ config, pkgs, ... }:

{
  # Font packages
  # Note: Removed fontbh100dpi due to conflict with fontadobe100dpi (both have fonts.dir)
  home.packages = with pkgs; [
    nerd-fonts.hack
    xorg.fontadobe75dpi
    xorg.fontadobe100dpi
    xorg.fontmiscmisc
    # xorg.fontbh100dpi  # Conflicts with fontadobe100dpi
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    wqy_zenhei
    source-han-sans
    source-han-serif
  ];
}
