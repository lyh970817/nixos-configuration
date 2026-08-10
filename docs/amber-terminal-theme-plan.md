# Amber Terminal Theme Plan

## Objective

Create a dark desktop that is believable as a modern laptop, while translating
the visual and interaction grammar of an amber monochrome terminal as faithfully
as practical. Historical authenticity comes before decoration, but simulated
CRT construction must not make the laptop look like it is wearing a filter.

The existing light theme remains an independent, unchanged high-contrast mode.

## Design priorities

Apply these priorities in order:

1. The result must be believable on the physical modern laptop.
2. It should use historically grounded monochrome-terminal conventions.
3. It should be attractive and comfortable for daily use.

When two goals conflict, prefer a functional translation of the terminal over
a literal simulation of its hardware.

## Core interpretation

The target is a modern operator console informed by a VT220, not CRT cosplay.

Authenticity should come primarily from:

- one amber hue expressed through luminance;
- warm near-black opaque surfaces;
- reverse-video selection and critical states;
- block cursors;
- text-first, keyboard-first interaction;
- compact square geometry;
- thin separators and borders;
- brightness, weight, underline, and inversion as semantic tools;
- restrained motion and no gratuitous animation.

Do not use:

- scanlines or raster-gap fonts;
- curvature, tilt, or geometric displacement;
- vignette or CRT bezel simulation;
- shadow masks or RGB phosphor patterns;
- global color-channel separation;
- animated static, flicker, jitter, or phosphor trails;
- fake burn-in, serial glitches, latency, or boot noise;
- translucent glass, neon borders, gradients, or rounded cards.

## Typography

Use Hack Nerd Font for terminal and TUI surfaces. It is a more credible modern
translation than Glass TTY: it preserves daily readability and symbol coverage
without embedding CRT raster gaps into every glyph.

Use normal system sans-serif fonts in modern GUI applications. Do not force a
monospace font onto content that is not terminal-like.

## Palette grammar

Treat amber as a tonal ramp rather than a collection of replacement hues.

| Token | Starting value | Purpose |
| --- | --- | --- |
| Background | `#080705` | Main warm black |
| Deep surface | `#0C0A06` | Panels and recessed areas |
| Border | `#2A2011` | Inactive structure |
| Muted | `#6E501D` | Comments and secondary text |
| Secondary | `#9B6D24` | Supporting information |
| Accent | `#BE842A` | Focus and active controls |
| Foreground | `#D99B32` | Primary text |
| Bright | `#FFD064` | Exceptional emphasis |

Semantic rules:

- Primary content uses normal amber.
- Secondary content uses dim amber.
- Focus uses a medium amber edge or reverse video.
- Selection uses dark text on amber.
- Links use underline rather than another hue.
- Warnings use brightness plus a label or border.
- Errors and destructive actions use inversion plus a textual or symbolic cue.
- Disabled state uses dim amber without transparency.

Retain a non-amber emergency hue only where monochrome treatment would make an
important state ambiguous.

## Full-screen display treatment

The shader is the only layer allowed to simulate display optics. Components
must not add their own glow.

Accepted effects:

- restrained spatial diffusion;
- luminance-gated bloom around bright edges;
- slightly raised warm blacks;
- subtle asymmetric backlight bleed;
- static, low-amplitude dark-field panel mura.

The first two echo the diffuse luminous character of an old phosphor display.
The last three are plausible imperfections of a lower-quality modern LCD and
connect the historical theme to the actual laptop.

All effects must remain geometrically uniform. Light mode disables the shader
completely. Fullscreen video, image work, presentations, remote desktops, and
color-sensitive tasks should eventually receive an explicit bypass.

Screenshots made through `grim` do not reliably contain Hyprland's final screen
shader pass. Judge shader tuning directly on the physical display. Use an
obvious temporary proof shader when verifying that the mechanism is active.

## Surface categories

### Full terminal treatment

Apply the complete amber palette and terminal interaction grammar to:

- Foot;
- shell prompts and Tmux;
- FZF and Newt/nmtui;
- Neovim;
- Yazi;
- btop and htop;
- Claude Code, Pi, OMP, and Herdr;
- other textual dashboards and diagnostic tools.

Use reverse video, luminance, weight, underline, and textual signs so important
semantics do not depend on hue.

### Terminal-inspired desktop chrome

Apply square opaque geometry, compact spacing, thin amber borders, and
keyboard-first interaction to:

- Hyprland window borders;
- Rofi;
- Mako;
- lock and authentication surfaces;
- clipboard, OCR, screenshot, and input-method popovers;
- GTK and Qt chrome where practical.

These surfaces should look like modern software designed with terminal-era
discipline, not like terminal emulator windows.

### Chrome-only treatment

Theme controls but preserve content colors in:

- browsers and developer tools;
- PDF and document viewers;
- LibreOffice and Calibre;
- image and media viewers;
- maps, charts, and rich web applications.

Never recolor photographs, video, documents, websites, or color-critical work
into amber merely to make the desktop uniform.

### Exempt surfaces

Shader bypass should be available for:

- photographs and video;
- image editing and color picking;
- screen sharing and external presentations;
- remote desktop sessions;
- color-sensitive charts and visualizations.

## Theme architecture

Preserve the repository's two-layer model:

```text
Desktop mode
  -> Hyprland, shader, wallpaper, GTK, Rofi, Mako, terminal profile

Session mode
  -> THEME_MODE frozen for shell, tmux, SSH/mosh, TUI, and editor sessions
```

Existing long-running sessions should not change unexpectedly when the local
display mode changes.

Create a single Nix palette source before extending the theme further. Generate
or derive consumer-specific values from it to prevent drift between terminals,
editors, launchers, notifications, and TUIs.

`switch-dark` and `switch-light` should restore every state explicitly. Dark
mode should enable the shader last; light mode should disable it first.

## Current operator-console direction

### Hyprland

- Opaque active and inactive windows.
- Square corners.
- One-pixel borders.
- Medium amber active border and dim amber inactive border.
- Compact but usable gaps.
- No compositor blur, shadow, or animation.

### Rofi

- Original six-row height and compact row padding.
- Square one-pixel frame.
- No application icons.
- Reverse-video selection using medium amber.
- Opaque background and Hack Nerd Font.
- No component-level glow.

### Mako

- Original summary and body content, without forced application-name prefixes.
- Square, opaque notification with a one-pixel border.
- Compact padding and restrained width.
- No large colored application icons in dark mode.
- Dim amber for low urgency and reverse video for critical urgency.

### Yazi

- Amber luminance hierarchy for file names and state.
- Avoid upstream multicolor application-logo icons.
- Prefer restrained terminal markers or monochrome icons.
- Preserve light flavor behavior separately.

## Rollout

1. Establish the honest baseline: Hack font, amber palette, no CRT geometry.
2. Tune physical-screen diffusion and bloom directly on the laptop.
3. Tune plausible LCD imperfections conservatively.
4. Apply operator-console geometry to core desktop controls.
5. Centralize palette tokens.
6. Migrate terminal and TUI consumers.
7. Add GTK 4, Qt, browser-chrome, document, and input-method integration.
8. Add shader bypasses for media and color-sensitive work.
9. Consider virtual-console and boot styling last.

## Validation criteria

- Straight lines remain straight.
- No scanline, curvature, tilt, vignette, or color-fringing artifact exists.
- Bloom is visible on the physical display without destroying body text.
- The terminal remains comfortable for extended use.
- Focus and selection are clear without relying on hue.
- Errors and destructive actions remain unambiguous.
- Windows, Rofi, and Mako remain compact, square, and opaque.
- Websites, photographs, documents, and video retain their real colors.
- Light mode clears every dark-only shader and restores its previous geometry.
- Existing remote sessions retain their selected mode.
- Dark/light switching leaves no stale compositor or configuration state.

## Historical references

- [DEC VT220 Technical Manual](https://bitsavers.org/pdf/dec/terminal/vt220/EK-VT220-TM-001_VT220_Technical_Manual_Nov84.pdf)
- [DEC VT220 Owner's Manual](https://bitsavers.org/pdf/dec/terminal/vt220/EK-VT220_UG-003_VT220_Owners_Manual_198412.pdf)
- [VT220 Programmer Reference](https://vt100.net/docs/vt220-rm/chapter4.html)
- [Glass TTY design notes](https://caglrc.cc/glasstty/)
- [AAPM display-performance report](https://www.aapm.org/pubs/reports/OR_03.pdf)
