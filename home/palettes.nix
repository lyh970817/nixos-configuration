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

    # P1 phosphor green, fitted rung for rung to the amber ladder above so the
    # two are structurally interchangeable: same rung count, same ordering,
    # same role per rung. Only the hue differs, so every program that reaches
    # colour through an ANSI slot follows the swap untouched.
    #
    # This is the vivid cut (foreground saturation 0.57). A greyer revision at
    # 0.48 was tried and reverted: desaturating adds blue, which costs daytime
    # melanopic exposure and reads less like a real P1 phosphor — a narrow-band
    # emitter is saturated by nature.
    #
    # The three middle rungs are placed by luminance, not by eye. The first cut
    # matched hue per rung and let luminance fall where it would, and the
    # middle of the ladder collapsed: as a fraction of the foreground it sits
    # under, mutedText landed at 0.119 where amber's is 0.238, and
    # secondaryText at 0.320 where amber's is 0.469, while both ends of the
    # ladder stayed within 1.02-1.18x of amber. Every role that has to be dim
    # but still readable broke at once — nmtui body text, the rofi, foot and
    # alacritty selections, btop's selected process, mako's low-urgency
    # notifications, fastfetch's parenthesised values.
    #
    # These reproduce amber's rung-to-rung spacing to within 0.02: 1.95x,
    # 1.53x and 1.38x against amber's 1.97x, 1.53x and 1.39x. Note the fix
    # anchors on the ratio to foreground rather than on amber's absolute
    # luminance: the vivid green foreground is itself only 0.84x amber's, so
    # matching absolutes squeezes accent up against it and costs a rung.
    # Every rung's hue ratios are carried over from the first cut unchanged.
    green = {
      background = "050806";
      deepSurface = "080C09";
      raisedBlack = "0B120D";
      subtleBorder = "15261A";
      mutedText = "245A2E";
      secondaryText = "307C3B";
      accent = "40964C";
      foreground = "4BAE55";
      bright = "65C96D";
      hot = "86E68C";
    };
  };
  # Profiles that exist only to be looked at side by side. They are written out
  # as terminal themes like any other profile, but are never sensible choices
  # for `active`. Currently empty; the night-mode comparison profiles that used
  # to live here were removed with the retired green -> amber transform.
  previewProfiles = { };
in
{
  inherit profiles previewProfiles;

  # The profile that dark mode is generated from. Flip this one name and
  # rebuild to change every terminal at once. Each profile is *also* written
  # out under its own name (themes/dark-amber.*, themes/dark-green.*), so the
  # two can be compared live by repointing the terminal's theme symlink without
  # a rebuild.
  activeName = "green";
  active = profiles.green;

  # The second phosphor baked into the same terminal config alongside the
  # active one. Foot holds two complete themes at once and switches between
  # them on a signal, so this one is reachable instantly at runtime with no
  # rebuild — that is what the `phosphor` command drives. Consumers that
  # hardcode hex rather than naming an ANSI slot cannot follow that switch and
  # stay on whichever profile was built.
  alternateName = "amber";
  alternate = profiles.amber;
}
