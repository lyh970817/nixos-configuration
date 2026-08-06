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
      import curses
      import pathlib
      import sys

      art = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
      art_width = max(map(len, art))

      def draw(screen):
          try:
              curses.curs_set(0)
          except curses.error:
              pass

          screen.timeout(1000)
          while True:
              height, width = screen.getmaxyx()
              top = max(0, (height - len(art)) // 2)
              left = max(0, (width - art_width) // 2)
              screen.erase()

              for row, line in enumerate(art[:height]):
                  try:
                      screen.addstr(top + row, left, line[: max(0, width - left)])
                  except curses.error:
                      pass

              screen.refresh()
              if screen.getch() in (ord("q"), 27):
                  return

      curses.wrapper(draw)
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
