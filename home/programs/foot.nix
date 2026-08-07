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
    background=000000
    foreground=4AB34D
    selection-foreground=000000
    selection-background=2E9031
    regular0=0C3A0E
    regular1=126D15
    regular2=207F23
    regular3=2E9031
    regular4=3CA23F
    regular5=4AB34D
    regular6=3CA23F
    regular7=2E9031
    bright0=126D15
    bright1=207F23
    bright2=7CDC7F
    bright3=3CA23F
    bright4=63C766
    bright5=4AB34D
    bright6=4AB34D
    bright7=4AB34D
    dim0=045C07
    dim1=045C07
    dim2=126D15
    dim3=207F23
    dim4=207F23
    dim5=2E9031
    dim6=207F23
    dim7=2E9031
    search-box-no-match=000000 3CA23F
    search-box-match=000000 4AB34D
    jump-labels=000000 4AB34D
    scrollback-indicator=4AB34D 045C07

    [cursor]
    color=000000 3CA23F
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

    [cursor]
    color=FFFFFF 000000
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
