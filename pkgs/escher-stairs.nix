{
  lib,
  python3,
  writeTextFile,
}:

# Escher-inspired impossible staircase animation, drawn with box-drawing
# characters through the Python standard-library curses module. Used as the
# hyprwinwrap animated terminal wallpaper (see home/desktop/escher-wallpaper.nix),
# but also runnable by hand in any terminal.
writeTextFile {
  name = "escher-stairs";
  destination = "/bin/escher-stairs";
  executable = true;
  text = "#!${python3.interpreter}\n" + builtins.readFile ./escher-stairs.py;
  checkPhase = ''
    ${python3.interpreter} -m py_compile "$out/bin/escher-stairs"
  '';

  meta = {
    description = "Animated Escher-inspired impossible staircase for the terminal";
    mainProgram = "escher-stairs";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
