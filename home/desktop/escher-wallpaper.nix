{ pkgs, ... }:

let
  # hyprwinwrap adopts any window with this class and renders it as the desktop
  # background layer, below every normal window. The class is the only handle
  # between the plugin config and the launcher, so keep the two in sync.
  wallpaperClass = "escher-wallpaper";

  # Padding off and opacity pinned: this window is the background, so every
  # pixel of it should be animation, and Hyprland must not dim it.
  wallpaperTerminal = "${pkgs.alacritty}/bin/alacritty --class ${wallpaperClass}"
    + " -o window.dynamic_padding=false"
    + " -o window.padding.x=0"
    + " -o window.padding.y=0"
    + " -o window.opacity=1.0"
    # 24 steps fills most of a 1080p screen; the animation shrinks itself on
    # smaller outputs, so this is an upper bound rather than a fixed size.
    + " --command ${pkgs.escher-stairs}/bin/escher-stairs --fps 6 --steps 24 --no-stars";
in
{
  # Also useful straight from a normal terminal.
  home.packages = [ pkgs.escher-stairs ];

  # Sourced from dotfiles/hypr/hyprland.conf. Generated rather than checked in
  # because the plugin path is a store path.
  xdg.configFile."hypr/wallpaper.conf".text = ''
    # Animated terminal wallpaper — see home/desktop/escher-wallpaper.nix.
    # The window itself is started by the escher-wallpaper user service, which
    # the dark/light mode hooks start and stop (light mode wants its own
    # image wallpaper visible instead).
    plugin = ${pkgs.hyprlandPlugins.hyprwinwrap}/lib/libhyprwinwrap.so

    plugin {
        hyprwinwrap {
            class = ^(${wallpaperClass})$
        }
    }

    windowrule {
        name = escher-wallpaper
        match:class = ^(${wallpaperClass})$
        # Background windows are never focused, so exempt from inactive_opacity
        # dimming; no decoration on something that is standing in for wallpaper.
        opacity = 1.0 override
        border_size = 0
        rounding = 0
        no_focus = true
    }
  '';

  systemd.user.services.escher-wallpaper = {
    Unit = {
      Description = "Animated Escher staircase terminal wallpaper";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = wallpaperTerminal;
      # Started before the Wayland environment is imported into the systemd
      # user manager, alacritty exits immediately; each restart picks up the
      # then-current manager environment, so this converges on its own.
      Restart = "always";
      RestartSec = "2s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    # Deliberately no Install.WantedBy: the theme hooks own the lifecycle so
    # the animation never covers the light-mode image wallpaper.
  };
}
