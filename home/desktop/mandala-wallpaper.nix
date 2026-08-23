{ pkgs, ... }:

let
  wallpaperClass = "mandala-wallpaper";
  wallpaperArt = ../../assets/wallpapers/Mandala_braille.txt;

  wallpaperViewer = pkgs.writeTextFile {
    name = "mandala-wallpaper-viewer";
    destination = "/bin/mandala-wallpaper-viewer";
    executable = true;
    text = ''
      #!${pkgs.python3.interpreter}
      import math
      import os
      import pathlib
      import sys
      import time

      art = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
      cell_width = max(map(len, art))
      cell_height = len(art)
      dot_width = cell_width * 2
      dot_height = cell_height * 4
      dot_for_bit = (
          (0, 0), (0, 1), (0, 2), (1, 0),
          (1, 1), (1, 2), (0, 3), (1, 3),
      )

      source_dots = set()
      for cell_y, line in enumerate(art):
          for cell_x, glyph in enumerate(line):
              mask = ord(glyph) - 0x2800
              if not 0 <= mask <= 0xFF:
                  continue
              for bit, (dot_x, dot_y) in enumerate(dot_for_bit):
                  if mask & (1 << bit):
                      source_dots.add((cell_x * 2 + dot_x, cell_y * 4 + dot_y))

      # Coordinates inherited from the 320x180 conversion. The circular region
      # rotates independently; branches and leaves outside it remain still.
      circle_x = 109.0
      circle_y = 92.0
      circle_radius_squared = 70.0 ** 2
      rotation_period = 90.0
      frame_interval = 0.2

      def make_frame(angle):
          cosine = math.cos(angle)
          sine = math.sin(angle)
          output_dots = set()

          for y in range(dot_height):
              dy = y - circle_y
              for x in range(dot_width):
                  dx = x - circle_x
                  if dx * dx + dy * dy <= circle_radius_squared:
                      source_x = round(circle_x + cosine * dx + sine * dy)
                      source_y = round(circle_y - sine * dx + cosine * dy)
                      lit = (source_x, source_y) in source_dots
                  else:
                      lit = (x, y) in source_dots

                  if lit:
                      output_dots.add((x, y))

          lines = []
          for cell_y in range(cell_height):
              glyphs = []
              for cell_x in range(cell_width):
                  mask = 0
                  for bit, (dot_x, dot_y) in enumerate(dot_for_bit):
                      if (
                          cell_x * 2 + dot_x,
                          cell_y * 4 + dot_y,
                      ) in output_dots:
                          mask |= 1 << bit
                  glyphs.append(chr(0x2800 + mask) if mask else " ")
              lines.append("".join(glyphs))
          return lines

      def render(lines, previous_size):
          width, height = os.get_terminal_size()
          top = max(0, (height - cell_height) // 2)
          left = max(0, (width - cell_width) // 2)
          visible_art = lines[: max(0, height - top)]
          size = (width, height)
          output = ["\033[?25l"]
          if size != previous_size:
              output.append("\033[2J")
          for row, line in enumerate(visible_art):
              output.append(
                  f"\033[{top + row + 1};{left + 1}H"
                  + line[: max(0, width - left)]
              )
          sys.stdout.write("".join(output))
          sys.stdout.flush()
          return size

      started = time.monotonic()
      next_frame = started
      previous_size = None
      try:
          while True:
              elapsed = time.monotonic() - started
              angle = elapsed * math.tau / rotation_period
              previous_size = render(make_frame(angle), previous_size)
              next_frame += frame_interval
              time.sleep(max(0.0, next_frame - time.monotonic()))
      finally:
          sys.stdout.write("\033[?25h")
          sys.stdout.flush()
    '';
  };

  wallpaperTerminal = pkgs.writeShellApplication {
    name = "mandala-terminal-wallpaper";
    runtimeInputs = [ pkgs.kitty ];
    text = ''
      # --class is what the Hyprland windowrule below matches on Wayland
      # (`match:class` reads the app id). window_padding_width=0 keeps the art
      # flush to the window edge; background_opacity pins the glass fully
      # opaque regardless of what kitty.conf might come to say.
      exec kitty \
        --class=${wallpaperClass} \
        -o window_padding_width=0 \
        -o background_opacity=1.0 \
        ${wallpaperViewer}/bin/mandala-wallpaper-viewer ${wallpaperArt}
    '';
  };
in
{
  home.packages = [ wallpaperTerminal ];

  xdg.dataFile."wallpapers/Mandala_braille.txt".source = wallpaperArt;

  # Included by hyprland.lua, so the file must exist even while the
  # wallpaper is disabled. hyprwinwrap was dropped from hyprland-plugins
  # upstream in v0.56.0 ("all: drop unmaintained plugins") and its last fix
  # targeted Hyprland 0.54.3, so no build of it can load into Hyprland 0.56.
  # The plugin wiring and the systemd unit are removed until the viewer is
  # ported to a native layer-shell surface (`kitten panel --edge=background`);
  # the theming hooks tolerate the missing unit. The windowrule stays so a
  # manually launched viewer still renders frameless.
  xdg.configFile."hypr/wallpaper.lua".text = ''
    hl.window_rule({
      name = "mandala-wallpaper",
      match = { class = "^(${wallpaperClass})$" },
      opacity = "1.0 override",
      border_size = 0,
      rounding = 0,
      no_focus = true,
    })
  '';

  # TRANSITIONAL twin of the rule above in the legacy hyprlang format, sourced
  # by dotfiles/hypr/hyprland.conf, for a compositor that started before the
  # migration and therefore cannot load Lua. See the header of that file for
  # why a frozen legacy set cannot drift, and for when this gets deleted.
  # Both are generated from the same `wallpaperClass`, so the match pattern
  # cannot disagree between the two dialects.
  xdg.configFile."hypr/wallpaper.conf".text = ''
    windowrule {
        name = mandala-wallpaper
        match:class = ^(${wallpaperClass})$
        opacity = 1.0 override
        border_size = 0
        rounding = 0
        no_focus = true
    }
  '';
}
