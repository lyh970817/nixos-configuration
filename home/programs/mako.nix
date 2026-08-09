# Mako Notification Daemon Configuration
# Managed by home-manager
# Original: ~/.config/mako/config
# Theme switching handled by darkman hooks via makoctl mode
{ config, pkgs, ... }:

let
  # Active phosphor profile; see ../palettes.nix.
  p = (import ../palettes.nix).active;
in

{
  services.mako = {
    enable = true;
    settings = {
      font = "Hack Nerd Font 12";
      background-color = "#ffffff";
      text-color = "#000000";
      width = 450;
      height = 400;
      margin = "10";
      padding = "10";
      border-size = 2;
      border-color = "#000000";
      border-radius = 4;
      icons = true;
      max-icon-size = 64;
      anchor = "top-right";
      default-timeout = 10000;
      layer = "overlay";
      max-visible = 5;
      format = "<b>%s</b>\\n%b";
    };

    extraConfig = ''
      [urgency=critical]
      background-color=#000000
      text-color=#ffffff
      border-color=#000000

      [mode=dark]
      # VT220-inspired operator-console treatment, built to rofi's box model so
      # the two surfaces read as one design (see home/programs/rofi.nix). Rofi's
      # dark.rasi nests three boxes; mako has only border + padding + a Pango
      # layout, so each rofi number is transplanted to the mako lever that lands
      # in the same place, all measured at 96 dpi with Hack Nerd Font 12:
      #
      #   rofi window border 1px            -> border-size=1
      #   rofi window border-radius 4px     -> border-radius=4
      #   rofi window padding 5px           -> padding's vertical value
      #   + rofi element padding 3px 6px    -> horizontal 5+6=11; the vertical 3
      #                                        comes from line_height below
      #
      # That puts text 12px in from the left frame edge and 12px down from the
      # top one, which is what a rofi row measures. A single padding=N cannot do
      # this: rofi's horizontal and vertical insets differ by 6px because its
      # rows are wider-padded than they are tall-padded.
      #
      # line_height=1.35 is the piece with no mako option behind it. Rofi gives
      # every row a 27px band around a 21px line; mako stacks its two lines at
      # 20px with no leading at all, which is what made the summary and body
      # read as one cramped block rather than as two rofi rows. Pango splits the
      # extra as half-leading above and below each line, so 1.35 * 20 = 27
      # reproduces rofi's rhythm exactly, on wrapped body lines too, and the 3px
      # above the first line supplies the element padding left out of padding=.
      font=Hack Nerd Font 12
      background-color=#${p.background}
      text-color=#${p.foreground}
      width=400
      height=400
      margin=10
      padding=5,11
      border-size=1
      border-color=#${p.accent}
      border-radius=4
      icons=0
      anchor=top-right
      default-timeout=10000
      layer=overlay
      max-visible=5
      format=<span line_height="1.35"><b>%s</b>\n%b</span>

      # Summary and body stay on rofi's single 12pt size; a second size would
      # break the type scale the two surfaces share. The summary is marked with
      # weight instead. Rofi separates its prompt from its placeholder by
      # brightness rung, which would be the closer quotation, but mako's colour
      # channel is already spoken for: the urgency sections below set text-color
      # per notification, and a colour hardcoded in format= overrides them --
      # critical urgency inverts to background-on-foreground, so a pinned green
      # body would vanish into the bright green fill.

      # An empty body would otherwise leave format='s \n as a blank line, giving
      # body-less notifications the height of two-line ones.
      [body="" mode=dark]
      format=<span line_height="1.35"><b>%s</b></span>

      # Low urgency notifications - deliberately dimmer than normal urgency.
      # accent rather than secondaryText: this is body text on the background,
      # and the green ladder's secondaryText rung reads 2.9:1 there against the
      # 4.4:1 the amber profile gave. accent restores it without losing the
      # rung of separation from normal urgency, which uses foreground.
      [urgency=low mode=dark]
      background-color=#${p.background}
      text-color=#${p.accent}
      border-color=#${p.mutedText}

      # Normal urgency (default values above apply)
      [urgency=normal mode=dark]
      background-color=#${p.background}
      text-color=#${p.foreground}
      border-color=#${p.foreground}

      # Critical urgency - inverted with bright amber
      [urgency=critical mode=dark]
      background-color=#${p.foreground}
      text-color=#${p.background}
      border-color=#${p.foreground}
      default-timeout=0
    '';
  };
}
