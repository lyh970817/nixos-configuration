# Phosphor palettes for the CRT console terminal themes.
#
# A profile is ten rungs of rising luminance over a near-black background. Every
# terminal slot is assigned by *rung name*, never by hex, so a new phosphor only
# has to supply ten colours to inherit the whole emphasis hierarchy that was
# tuned against amber — including the deliberate irregularities that individual
# TUIs were fitted to:
#
#   raisedBlack    ANSI black, lifted off the background so a selected row
#                  painted in ANSI black stays visible.
#   secondaryText  ANSI white, receded *below* the foreground so SGR-37
#                  secondary text (menu descriptions, hints) reads as secondary.
#   hot            ANSI bright green, lifted *above* the foreground so bright
#                  emphasis (selected menu entries) is distinguishable.
#   bright         ANSI bright blue, between foreground and hot so fuzzy-match
#                  fragments read as accents rather than glare.
#
# Because those choices are positional, a profile swap carries them across
# without retuning the programs that depend on them. Programs that hardcode hex
# instead of naming an ANSI slot (fzf, newt, btop, mako, hypr, yazi) are not
# covered by this file and stay on whatever hexes they name.
#
# Hexes are stored bare; consumers add their own "#" prefix if the format needs
# one. Rungs are listed darkest to brightest, which is the order every ladder
# must preserve.
let
  profiles = {
    # VT220 amber. The reference ladder; every other profile is fitted to it
    # rung for rung, so the two are structurally interchangeable.
    amber = {
      background = "080705";
      deepSurface = "0C0A06";
      raisedBlack = "110E08";
      subtleBorder = "2A2011";
      mutedText = "6E501D";
      secondaryText = "9B6D24";
      accent = "BE842A";
      foreground = "D99B32";
      bright = "EDB144";
      hot = "FFD064";
    };

  };
in
{
  inherit profiles;

  # The profile that dark mode is generated from. Flip this one name and
  # rebuild to change every terminal at once. Each profile is *also* written
  # out under its own name (themes/dark-amber.*, themes/dark-green.*), so the
  # two can be compared live by repointing the terminal's theme symlink without
  # a rebuild.
  activeName = "amber";
  active = profiles.amber;
}
