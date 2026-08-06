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

      def render(lines, first_frame):
          width, height = os.get_terminal_size()
          top = max(0, (height - cell_height) // 2)
          left = max(0, (width - cell_width) // 2)
          visible_art = lines[: max(0, height - top)]
          positioned = [""] * top + [
              " " * left + line[: max(0, width - left)]
              for line in visible_art
          ]
          prefix = "\033[2J\033[H\033[?25l" if first_frame else "\033[H"
          sys.stdout.write(prefix + "\n".join(positioned))
          sys.stdout.flush()

      started = time.monotonic()
      next_frame = started
      first_frame = True
      try:
          while True:
              elapsed = time.monotonic() - started
              angle = elapsed * math.tau / rotation_period
              render(make_frame(angle), first_frame)
              first_frame = False
              next_frame += frame_interval
              time.sleep(max(0.0, next_frame - time.monotonic()))
      finally:
          sys.stdout.write("\033[?25h")
          sys.stdout.flush()
    '';
  };

  wallpaperTerminal = pkgs.writeShellApplication {
    name = "mandala-terminal-wallpaper";
    runtimeInputs = [ pkgs.alacritty ];
    text = ''
      exec alacritty \
        --class ${wallpaperClass} \
        -o window.dynamic_padding=false \
        -o window.padding.x=0 \
        -o window.padding.y=0 \
        -o window.opacity=1.0 \
        --command ${wallpaperViewer}/bin/mandala-wallpaper-viewer ${wallpaperArt}
    '';
  };
in
{
  home.packages = [ wallpaperTerminal ];

  xdg.dataFile."wallpapers/Mandala_braille.txt".source = wallpaperArt;

  # Sourced from hyprland.conf. hyprwinwrap compares its class as a literal
  # string; unlike a normal window rule, a regex here silently fails.
  xdg.configFile."hypr/wallpaper.conf".text = ''
    plugin = ${pkgs.hyprlandPlugins.hyprwinwrap}/lib/libhyprwinwrap.so

    plugin {
        hyprwinwrap {
            class = ${wallpaperClass}
        }
    }

    windowrule {
        name = mandala-wallpaper
        match:class = ^(${wallpaperClass})$
        opacity = 1.0 override
        border_size = 0
        rounding = 0
        no_focus = true
    }
  '';

  systemd.user.services.mandala-wallpaper = {
    Unit = {
      Description = "Braille mandala terminal wallpaper";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${wallpaperTerminal}/bin/mandala-terminal-wallpaper";
      Restart = "always";
      RestartSec = "2s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    # Dark/light mode hooks own this service's lifecycle.
  };
}
