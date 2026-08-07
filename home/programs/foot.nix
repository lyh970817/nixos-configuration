# Foot Terminal Configuration
# Managed by Home Manager alongside Alacritty.
{ lib, pkgs, ... }:

let
  palettes = import ../palettes.nix;

  darkFonts = ''
    font=Hack Nerd Font:size=12
    font-bold=Hack Nerd Font:style=Bold:size=12
    font-italic=Hack Nerd Font:style=Italic:size=12
    font-bold-italic=Hack Nerd Font:style=Bold Italic:size=12
    pad=8x8 center
  '';

  lightFonts = ''
    font=Hack Nerd Font:size=11
    font-bold=Hack Nerd Font:style=Bold:size=11
    font-italic=Hack Nerd Font:style=Italic:size=11
    font-bold-italic=Hack Nerd Font:style=Bold Italic:size=11
    pad=10x10 center
  '';

  common = ''
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

  # Dark palette, addressed by ladder rung rather than by hex so any phosphor
  # profile in ../palettes.nix produces the same emphasis hierarchy. See that
  # file for why regular0, regular7, bright2, and bright4 sit where they do.
  mkDarkTheme = section: p: ''
    [${section}]
    background=${p.background}
    foreground=${p.foreground}
    selection-foreground=${p.background}
    # accent, not secondaryText: the selection carries background-coloured
    # text, and the green ladder's secondaryText rung is only 0.58x the
    # luminance of amber's, which drops that pairing to 2.9:1. See rofi.nix.
    selection-background=${p.accent}
    regular0=${p.raisedBlack}
    regular1=${p.subtleBorder}
    regular2=${p.mutedText}
    regular3=${p.secondaryText}
    regular4=${p.accent}
    regular5=${p.foreground}
    regular6=${p.accent}
    regular7=${p.secondaryText}
    bright0=${p.subtleBorder}
    bright1=${p.mutedText}
    bright2=${p.hot}
    bright3=${p.accent}
    bright4=${p.bright}
    bright5=${p.foreground}
    bright6=${p.foreground}
    bright7=${p.foreground}
    dim0=${p.deepSurface}
    dim1=${p.deepSurface}
    dim2=${p.subtleBorder}
    dim3=${p.mutedText}
    dim4=${p.mutedText}
    dim5=${p.secondaryText}
    dim6=${p.mutedText}
    dim7=${p.secondaryText}
    search-box-no-match=${p.background} ${p.accent}
    search-box-match=${p.background} ${p.foreground}
    jump-labels=${p.background} ${p.foreground}
    scrollback-indicator=${p.foreground} ${p.deepSurface}
    cursor=${p.background} ${p.accent}
  '';

  # Foot carries two complete colour themes in one config and switches between
  # them at runtime on SIGUSR1/SIGUSR2, with no reload and no relaunch. That is
  # what makes an instant real green/amber swap possible. Values are explicitly
  # *not* inherited from [colors] into [colors2], so both blocks are written in
  # full. See the `phosphor` command in ../desktop/phosphor-switch.nix.
  mkDarkConfig =
    primary: secondary:
    darkFonts + common + mkDarkTheme "colors" primary + mkDarkTheme "colors2" secondary;

  # A per-profile file gets the same palette in both slots, so signalling one of
  # these is a harmless no-op rather than a surprise switch to something else.
  mkSoloConfig = p: mkDarkConfig p p;

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
    # The theme the dark-mode hook links to: active phosphor in slot 1, the
    # alternate in slot 2.
    ".config/foot/themes/dark.ini".text = mkDarkConfig palettes.active palettes.alternate;

    # The same pair the other way round. `phosphor` relinks foot.ini at this
    # when the alternate is selected, so newly opened windows agree with the
    # ones already switched by signal.
    ".config/foot/themes/dark-swapped.ini".text = mkDarkConfig palettes.alternate palettes.active;

    ".config/foot/themes/light.ini".text = lightFonts + common + lightTheme;
  }
  # Every profile is also written under its own name so two phosphors can be
  # compared live: point a single window at one with `foot --config=`, or relink
  # ~/.config/foot/foot.ini. A dark/light switch puts the active profile back.
  // lib.mapAttrs' (
    name: p: lib.nameValuePair ".config/foot/themes/dark-${name}.ini" { text = mkSoloConfig p; }
  ) (palettes.profiles // palettes.previewProfiles);

  # The theme hooks replace this symlink when the desktop mode changes.
  systemd.user.tmpfiles.rules = [
    "L %h/.config/foot/foot.ini - - - - %h/.config/foot/themes/dark.ini"
  ];
}
