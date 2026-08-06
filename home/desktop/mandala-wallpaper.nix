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
      import os
      import pathlib
      import signal
      import sys
      import threading

      art = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
      art_width = max(map(len, art))
      resize_event = threading.Event()

      def mark_resize(_signum, _frame):
          resize_event.set()

      def render():
          width, height = os.get_terminal_size()
          top = max(0, (height - len(art)) // 2)
          left = max(0, (width - art_width) // 2)
          visible_art = art[: max(0, height - top)]
          output = ["\033[2J\033[H\033[?25l", "\n" * top]
          output.extend(
              " " * left + line[: max(0, width - left)] + "\n"
              for line in visible_art
          )
          sys.stdout.write("".join(output))
          sys.stdout.flush()

      signal.signal(signal.SIGWINCH, mark_resize)
      resize_event.set()
      try:
          while True:
              resize_event.wait()
              resize_event.clear()
              render()
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
