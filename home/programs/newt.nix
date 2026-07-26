# Newt (nmtui) Theme Files Configuration
# Managed by home-manager
# Original: ~/.config/newt/themes/
# Both dark and light variants are written unconditionally by this file;
# shell.nix selects which one to use per-session based on THEME_MODE and
# exports it as NEWT_COLORS.
{ config, pkgs, ... }:

{
  # Per-mode (dark/light) theme variant files, selected at shell startup by
  # THEME_MODE (set by theme-hold for ssh/mosh sessions, otherwise defaulted
  # from the local monitor)
  home.file = {
    ".config/newt/themes/dark".text = ''
      root=green,black:window=green,black:border=brightgreen,black:listbox=green,black:actlistbox=black,brightgreen:sellistbox=brightgreen,black:actsellistbox=black,green:textbox=green,black:acttextbox=brightgreen,black:entry=brightgreen,black:disentry=white,black:checkbox=green,black:actcheckbox=green,black:button=black,brightgreen:actbutton=green,black:compactbutton=green,black:actcompactbutton=black,brightgreen:label=brightgreen,black:title=brightgreen,black:roottext=green,black:emptyscale=green,black:fullscale=black,brightgreen:shadow=black,black
    '';

    ".config/newt/themes/light".text = ''
      root=black,white;window=black,white;border=black,white;textbox=black,white;button=white,black;compactbutton=black,white;actbutton=white,black;checkbox=black,white;actcheckbox=white,black;entry=black,white;disentry=gray,white;label=black,white;listbox=black,white;actlistbox=white,black;sellistbox=black,gray;actsellistbox=white,black
    '';
  };
}
