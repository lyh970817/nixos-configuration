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
    # text, which secondaryText only just supports even with the ladder
    # corrected (3.9:1). See home/palettes.nix.
    selection-background=${p.accent}
    regular0=${p.raisedBlack}
    # Claude Code's hardcoded chalk map (see regular2 below) puts
    # string/regexp/deletion here, and its ANSI theme fills removed diff
    # lines with it; at subtleBorder (1.27:1) both were invisible.
    # mutedText is the only free rung that lifts them, and it also rescues
    # git's stock red -- diff removals and dirty paths in `git status`.
    regular1=${p.mutedText}
    # Claude Code colours comments from a hardcoded highlight.js/chalk map, not
    # from its theme (dark-ansi has no syntax tokens at all), so ANSI green is
    # the only lever: secondaryText keeps comments below body text while
    # clearing the dim rung (3.9:1 against mutedText's 2.5:1). Yellow has to
    # move up with it -- that same map puts function names on ANSI yellow, and
    # regular7 already sits on secondaryText, so leaving yellow here would
    # render comments, function names and body text as one colour. See
    # home/palettes.nix.
    regular2=${p.secondaryText}
    regular3=${p.accent}
    regular4=${p.accent}
    regular5=${p.foreground}
    regular6=${p.accent}
    regular7=${p.secondaryText}
    bright0=${p.subtleBorder}
    # bright1 is Claude Code's error text, its logo, and the word-level fill
    # inside a removed diff line, which must stay distinct from that line's
    # own fill now that regular1 holds mutedText. secondaryText is the only
    # free rung above it and it keeps the usage ramp in
    # dotfiles/claude/statusline.sh ascending (91/93/92 = 3.9/5.5/13.1).
    bright1=${p.secondaryText}
    bright2=${p.hot}
    bright3=${p.accent}
    bright4=${p.bright}
    bright5=${p.foreground}
    bright6=${p.foreground}
    bright7=${p.foreground}
    dim0=${p.deepSurface}
    dim1=${p.deepSurface}
    # Claude Code dims comments inside its diff view, so code-block comments
    # land here rather than on regular2. At subtleBorder that put them at
    # 1.27:1 -- unreadable, and a whole rung below dim3/dim4/dim6 for no
    # reason. Match regular2 so a comment reads the same in a diff as in a
    # plain block.
    dim2=${p.secondaryText}
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
  # what makes an instant real green/amber swap possible. Since foot 1.26 the
  # sections are named [colors-dark] (SIGUSR1 slot, startup default) and
  # [colors-light] (SIGUSR2 slot) — the old [colors]/[colors2] names are
  # deprecated aliases with identical signal semantics; both slots here carry
  # dark phosphor palettes and are *not* inherited into each other, so both
  # blocks are written in full. See `phosphor` in ../desktop/phosphor-switch.nix.
  mkDarkConfig =
    primary: secondary:
    darkFonts + common + mkDarkTheme "colors-dark" primary + mkDarkTheme "colors-light" secondary;

  # A per-profile file gets the same palette in both slots, so signalling one of
  # these is a harmless no-op rather than a surprise switch to something else.
  mkSoloConfig = p: mkDarkConfig p p;

  lightTheme = ''
    [colors-dark]
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
