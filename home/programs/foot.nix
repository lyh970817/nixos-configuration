# Foot Terminal Configuration
# Managed by Home Manager alongside Alacritty.
{ pkgs, ... }:

let
  common = ''
    font=Hack Nerd Font:size=12
    font-bold=Hack Nerd Font:style=Bold:size=12
    font-italic=Hack Nerd Font:style=Italic:size=12
    font-bold-italic=Hack Nerd Font:style=Bold Italic:size=12
    pad=10x10 center
    selection-target=clipboard

    [cursor]
    style=block
    blink=yes
    blink-rate=500

    [key-bindings]
    primary-paste=none
    clipboard-paste=Control+Shift+v Shift+Insert

    # Preserve the explicit terminal sequences used by tmux, Codex, and Herdr.
    [text-bindings]
    \x1b[49;5u=Control+1
    \x1b[49;6u=Control+Shift+1
    \x1b[21;2~=Mod1+Shift+Return
    \x1b[13;5u=Control+Return
    \x1b[13;2u=Shift+Return
    \x1b[13;3u=Mod1+Return
  '';

  darkTheme = ''
    [colors]
    background=080705
    foreground=D99B32
    selection-foreground=080705
    selection-background=9B6D24
    regular0=110E08
    regular1=2A2011
    regular2=6E501D
    regular3=9B6D24
    regular4=BE842A
    regular5=D99B32
    regular6=BE842A
    regular7=9B6D24
    bright0=2A2011
    bright1=6E501D
    bright2=FFD064
    bright3=BE842A
    bright4=EDB144
    bright5=D99B32
    bright6=D99B32
    bright7=D99B32
    dim0=0C0A06
    dim1=0C0A06
    dim2=2A2011
    dim3=6E501D
    dim4=6E501D
    dim5=9B6D24
    dim6=6E501D
    dim7=9B6D24
    search-box-no-match=080705 BE842A
    search-box-match=080705 D99B32
    jump-labels=080705 D99B32
    scrollback-indicator=D99B32 0C0A06
    cursor=080705 BE842A
  '';

  lightTheme = ''
    [colors]
    background=FFFFFF
    foreground=000000
    selection-foreground=FFFFFF
    selection-background=000000
    regular0=000000
    regular1=000000
    regular2=000000
    regular3=000000
    regular4=000000
    regular5=000000
    regular6=000000
    regular7=FFFFFF
    bright0=808080
    bright1=808080
    bright2=808080
    bright3=808080
    bright4=808080
    bright5=808080
    bright6=808080
    bright7=FFFFFF
    dim0=000000
    dim1=000000
    dim2=000000
    dim3=000000
    dim4=000000
    dim5=000000
    dim6=000000
    dim7=FFFFFF
    search-box-no-match=FFFFFF 000000
    search-box-match=000000 FFFFFF
    jump-labels=FFFFFF 000000
    scrollback-indicator=000000 FFFFFF
    cursor=FFFFFF 000000
  '';
in
{
  home.packages = [ pkgs.foot ];

  home.file = {
    ".config/foot/themes/dark.ini".text = common + darkTheme;
    ".config/foot/themes/light.ini".text = builtins.replaceStrings [ "size=12" ] [ "size=11" ] common + lightTheme;
  };

  # The theme hooks replace this symlink when the desktop mode changes.
  systemd.user.tmpfiles.rules = [
    "L %h/.config/foot/foot.ini - - - - %h/.config/foot/themes/dark.ini"
  ];
}
