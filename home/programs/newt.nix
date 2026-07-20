# Newt (nmtui) Theme Files Configuration
# Managed by home-manager
# Original: ~/.config/newt/themes/
# Theme switching handled by darkman hooks (symlinks to current_theme)
# Consumed by shell.nix's NEWT_COLORS export via the current_theme symlink
# created by switch-dark/switch-light in desktop/theming.nix
{ config, pkgs, ... }:

{
  # Theme files for darkman switching
  home.file = {
    ".config/newt/themes/dark".text = ''
      root=green,black:window=green,black:border=brightgreen,black:listbox=green,black:actlistbox=black,brightgreen:sellistbox=brightgreen,black:actsellistbox=black,green:textbox=green,black:acttextbox=brightgreen,black:entry=brightgreen,black:disentry=white,black:checkbox=green,black:actcheckbox=green,black:button=black,brightgreen:actbutton=green,black:compactbutton=green,black:actcompactbutton=black,brightgreen:label=brightgreen,black:title=brightgreen,black:roottext=green,black:emptyscale=green,black:fullscale=black,brightgreen:shadow=black,black
    '';

    ".config/newt/themes/light".text = ''
      root=black,white;window=black,white;border=black,white;textbox=black,white;button=white,black;compactbutton=black,white;actbutton=white,black;checkbox=black,white;actcheckbox=white,black;entry=black,white;disentry=gray,white;label=black,white;listbox=black,white;actlistbox=white,black;sellistbox=black,gray;actsellistbox=white,black
    '';
  };
}
