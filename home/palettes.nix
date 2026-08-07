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
  # --- hex helpers, used to derive the night-comparison profile below ---
  hexDigits = {
    "0" = 0;
    "1" = 1;
    "2" = 2;
    "3" = 3;
    "4" = 4;
    "5" = 5;
    "6" = 6;
    "7" = 7;
    "8" = 8;
    "9" = 9;
    "A" = 10;
    "B" = 11;
    "C" = 12;
    "D" = 13;
    "E" = 14;
    "F" = 15;
  };
  hexChars = "0123456789ABCDEF";
  byteOf =
    s: i:
    16 * hexDigits.${builtins.substring (2 * i) 1 s} + hexDigits.${builtins.substring (2 * i + 1) 1 s};
  toByteHex =
    n:
    builtins.substring (builtins.div n 16) 1 hexChars
    + builtins.substring (n - 16 * (builtins.div n 16)) 1 hexChars;
  clampByte =
    n:
    if n > 255 then
      255
    else if n < 0 then
      0
    else
      n;
  round = x: builtins.floor (x + 0.5);

  # Scale one hex colour by a per-channel gain, rounding and clamping the way a
  # display would.
  scaleHex =
    gain: hex:
    builtins.concatStringsSep "" (
      builtins.map (i: toByteHex (clampByte (round (byteOf hex i * builtins.elemAt gain i)))) [
        0
        1
        2
      ]
    );
  scaleProfile = gain: builtins.mapAttrs (_: scaleHex gain);

  # Per-channel gains of the night-mode CTM. hyprsunset derives these from
  # temperature and gamma via a blackbody approximation; Nix has no logarithm
  # builtin, so they are transcribed from the matrix the service itself logs on
  # every profile load:
  #
  #   Calculated the CTM to be [mat3x3: 2.8, 0, 0, 0, 0.84989333, 0, 0, 0, 0]
  #
  # If nightTemperature or nightGamma in home/desktop/hyprsunset.nix changes,
  # re-read these from that log line — nothing here can recompute them.
  nightGain = [
    2.8
    0.84989333
    0.0
  ];

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
    # 0.48 was tried and reverted: desaturating narrows the spread of the
    # red:green gain the night-mode CTM has to supply (1.80-3.66 down to
    # 1.68-2.82) and so buys a closer amber, but it does that by adding blue,
    # which costs daytime melanopic exposure and reads less like a real P1
    # phosphor — a narrow-band emitter is saturated by nature. The vivid cut is
    # the deliberate choice; the amber fit pays for it by needing gamma 280%.
    # See docs/phosphor-palette-and-night-mode.md for the full trade-off, and
    # home/desktop/hyprsunset.nix for the matching night values.
    green = {
      background = "050806";
      deepSurface = "080C09";
      raisedBlack = "0B120D";
      subtleBorder = "15261A";
      mutedText = "193F20";
      secondaryText = "286731";
      accent = "3D8E48";
      foreground = "4BAE55";
      bright = "65C96D";
      hot = "86E68C";
    };
  };
  # Profiles that exist only to be looked at side by side. They are written out
  # as terminal themes like any other profile, but are never sensible choices
  # for `active`.
  previewProfiles = {
    # Amber, pre-divided by the night-mode gains, so that *while night mode is
    # on* a terminal using this profile renders as real amber. That makes a
    # genuine same-screen comparison possible: with night mode on, put this
    # window next to an ordinary green one and the left is the target, the
    # right is what the transform actually achieves — both under the identical
    # CTM, because a CTM applies per output and cannot be scoped to a window.
    #
    # The blue gain is zero and division by it is undefined, so blue is dropped
    # here too. That is not a shortcut: night mode annihilates blue for
    # everything on screen, so no reference shown under it can carry blue
    # either. The comparison is therefore honest about hue and lightness and
    # silent about amber's small blue component.
    #
    # With night mode *off* this profile looks like a harsh yellow-green. That
    # is expected; it is a pre-distorted image meant to be viewed through the
    # transform.
    amberViaNight = scaleProfile (builtins.map (
      g: if g == 0.0 then 0.0 else 1.0 / g
    ) nightGain) profiles.amber;

    # What the fit predicts green becomes under the night CTM, as a static
    # palette. Useful for judging the match with night mode *off*, though it
    # assumes the CTM multiplies encoded sRGB rather than linear light.
    greenAsNight = scaleProfile nightGain profiles.green;
  };
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
