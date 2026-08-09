# Matching mako notifications to rofi

Working notes for the change in `home/programs/mako.nix` that puts dark-mode
notifications on rofi's box model. Scope was dark mode only (the mode active at
task start); the light/default block in `services.mako.settings` is untouched.

## Why the earlier attempt failed

`ba577fdd Align Mako notification spacing with Rofi` changed exactly one line:

    -      padding=8
    +      padding=6

It was not a case of the setting never taking effect. The generated config was
checked back through the system generations: `padding=6` has been in the
installed `.config/mako/config` since generation 264 (2026-08-08 19:34), the
running mako started at 2026-08-09 11:57 and so read it, and the config content
(md5 `bfc348d1`) is byte-identical across every generation from 275 to 284 and
to the live file. The change applied. It just moved the wrong way, for two
reasons:

1. **It went in the wrong direction.** Rofi's text is *further* from its frame
   than mako's was, not closer. Rofi nests three boxes and their paddings add
   up: window border 1px + window padding 5px + element padding 6px = 12px from
   the frame to a list row's text. Mako had border 1 + padding 8 = 9px, already
   short of rofi; dropping to 6 took it to 7px and doubled the gap in the
   mismatch. Reading `padding: 5px` off `window {}` in the rasi and comparing it
   to mako's single `padding` is the trap — that 5px is only the outermost of
   three nested contributions.

2. **One number cannot express rofi's insets.** Rofi's element padding is
   `3px 6px`, so its horizontal and vertical insets differ by 6px. A scalar
   `padding=N` in mako can only produce a square inset. Mako accepts CSS-style
   directional values (`padding=vertical,horizontal`), which is what the fix
   uses.

Neither of those is visible from the config text, which is why the previous
attempt was never going to converge without rendering the two side by side.

## Measurements

All taken from `grim` captures of the real compositor at 96 dpi, Hack Nerd Font
12, threshold-and-profile analysis of the pixels rather than reading the config.

Rofi (`dotfiles`-free, theme is inline in `home/programs/rofi.nix`, dark.rasi):

| thing | px |
| --- | --- |
| window outer size | 990 x 203 |
| window border | 1 |
| window padding | 5 |
| inputbar padding | 4 vertical, 5 horizontal |
| element (list row) band | 27 |
| element padding | 3 vertical, 6 horizontal |
| text line, logical | 21 |
| row pitch | 27 |
| frame edge to row text, horizontal | 12 |
| frame edge to row text, vertical | 9-10 |

The 203px window height is fully accounted for:
`1 + 5 + (4+21+4) + 6*27 + 5 + 1 = 203`, which confirms the model.

Mako before:

| thing | px |
| --- | --- |
| popup outer size | 402 x 54 |
| border | 1 |
| padding | 6 (all four edges) |
| line pitch | 20 |
| frame edge to text | 7 |

So mako's text sat 5px closer to its frame than rofi's, on every edge, and its
two lines had zero leading against rofi's 6px of inter-row air.

## What changed and why those numbers

    padding=5,11
    border-size=1                     (unchanged)
    border-radius=4                   (unchanged)
    font=Hack Nerd Font 12            (unchanged)
    format=<span line_height="1.35"><b>%s</b>\n%b</span>

- `border-size=1`, `border-radius=4` already matched rofi's window; left alone.
- `padding=5,11` — the 5 is rofi's window padding. The 11 is rofi's window
  padding 5 plus its element padding 6, because horizontally there is no other
  mako lever to carry the element's share.
- `line_height="1.35"` carries the element's *vertical* 3px, and fixes the
  cramped two-line block at the same time. Rofi gives every row a 27px band
  around a 21px line; mako stacked lines at 20px with no leading. Pango
  distributes a `line_height` factor as half-leading above and below each line,
  so 1.35 x 20 = 27 reproduces rofi's row pitch exactly. The 3.5px it adds above
  the first line is the element's top padding; the 3.5px below the last is its
  bottom padding.

Measured result: popup 402 x 66, frame-to-text 12px horizontal and 12px
vertical, summary-to-body pitch 27px. Rofi's row is 12px and 27px. Verified on a
wrapped three-line body too — `line_height` applies to wrapped lines, so a long
body keeps the rhythm instead of compressing.

## The two texts

Both stay at 12pt, rofi's one and only size. A smaller body would introduce a
second size into a scale the two surfaces otherwise share, and 12pt is already
small enough that a step down reads as an accident. The summary is marked with
**weight** (`<b>`).

The closer quotation of rofi would have been brightness: rofi's inputbar
separates its prompt (`@fg`) from its placeholder (`@fg-alt`, the
`secondaryText` rung), and the phosphor palettes are built around exactly that
kind of rung pair. That variant was built and rendered
(`cand-d.conf` / `cmp-d.png`) and does look marginally more rofi-like. It was
rejected on function, not taste: mako's colour channel is already committed to
the urgency ladder. `[urgency=low|normal|critical mode=dark]` each set
`text-color`, and a colour hardcoded inside `format=` wins over `text-color`
unconditionally. Critical urgency inverts to background-on-foreground, so a
pinned `#307C3B` body would render dark green on the bright green fill and be
effectively invisible on exactly the notifications that matter most.

A `[body="" mode=dark]` section was added alongside. `format`'s `\n` renders as
a blank line when a notification has no body, so body-less notifications
("Screenshot saved") were as tall as two-line ones with an empty band beneath
the title. The extra section drops the `\n` for that case.

## Verification

`screen-verify` session `755d78f7f542d36d8f822e42`. Both surfaces were put on
the hidden staging output at the same time and captured in one frame, so they
are compared at identical scale with no resampling between them. Mako was
pointed at a writable preview config via
`screen-verify preview symlink --target ~/.config/mako/config` plus
`makoctl reload`; the installed `/nix/store` symlink was never edited and
`screen-verify end` restored it (verified: `~/.config/mako/config` resolves back
to `/nix/store/1m37qqg2gc6b4n7qbw3jhb1ccaqacrm8-hm_makoconfig`, the pre-session
target). No Home Manager activation or `nixos-rebuild` was run.

Screenshots, rofi on top and mako below at 1:1 then zoomed 2x:

- before: `/tmp/claude-1000/-home-andongni--nixos-config/5f734a75-d34c-44b5-9d17-48ad780ed332/scratchpad/cmp-before2.png`
- after: `/tmp/claude-1000/-home-andongni--nixos-config/5f734a75-d34c-44b5-9d17-48ad780ed332/scratchpad/cmp-final.png`
- colour-rung variant that was rejected: `.../scratchpad/cmp-d.png`
- edge cases, body-less and wrapped: `.../scratchpad/edge.png`

Those live in a session scratchpad and will not survive indefinitely; the
capture recipe is `scratchpad/both.sh`, which is reproducible against a fresh
`screen-verify begin`.

Still to do by whoever integrates this: `rebuild`, then confirm the installed
result through `screen-verify` per the repo's rebuild policy. mako does not
watch its config, so the rebuild must be followed by `makoctl reload` (or a
relogin) before the change is visible.
