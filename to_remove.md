
   antigravity                                                               Shell history shows 1 direct invocation; large    Strong candidate unless you actively use it. See home/
                                                                                             experimental/AI editor package    packages/development.nix:40. Closure about 1.0 GiB.
  ──────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────
   bottles, winetricks, steam-run                                           Large Wine stack; history shows steam-run used,    Keep only if Windows/WeChat/AppImage workflows still
                                                                                                     winetricks barely used    matter. See home/programs/wine.nix:4. Closures: Bottles
                                                                                                                               about 2.9 GiB, Steam-run about 1.6 GiB, Winetricks about
                                                                                                                               1.0 GiB, with overlap.
  ──────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────
   dconf-editor                                                      Typically one-off GUI settings editor; no usage signal    Safe to remove unless you actively inspect GNOME
                                                                                                                               settings. See home/packages/desktop.nix:34. Closure
                                                                                                                               about 300 MiB.
  ──────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────
   arc-theme, paper-gtk-theme                                        Current hooks use Trinity, HighContrast, Matrix-Icons,    Likely leftover theme packages. See home/packages/
                                                                                      Adwaita; Arc/Paper are not referenced    desktop.nix:32.
  ──────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────
   xorg.fontadobe75dpi, xorg.fontadobe100dpi, xorg.fontmiscmisc           Old bitmap X11 fonts; unlikely useful on a modern    Low disk impact, but likely unnecessary unless legacy
                                                                                                             Hyprland setup    X11 apps need them. See home/packages/fonts.nix:8.
  ──────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────
   pipx                                                                 History shows 1 direct invocation; you also have uv    If uv tool covers your Python CLI installs, pipx is
                                                                                                                               probably redundant. See home/packages/
                                                                                                                               development.nix:17.
   socat                                                                          History shows 1; niche networking utility    Keep only if you knowingly use it for debugging/proxy
