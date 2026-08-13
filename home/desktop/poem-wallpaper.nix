{
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  poemWallpaper = pkgs.stdenv.mkDerivation {
    pname = "vertical-poem-wallpaper";
    version = "1";
    src = ../../pkgs/vertical-poem-wallpaper.c;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [
      pkgs.gtk3
      pkgs.gtk-layer-shell
    ];
    buildPhase = ''
      $CC $NIX_CFLAGS_COMPILE \
        $(pkg-config --cflags gtk+-3.0 gtk-layer-shell-0) \
        "$src" -o vertical-poem-wallpaper \
        $(pkg-config --libs gtk+-3.0 gtk-layer-shell-0)
    '';
    installPhase = ''
      install -Dm755 vertical-poem-wallpaper \
        "$out/bin/vertical-poem-wallpaper"
    '';
  };

  poemWallpaperLauncher = pkgs.writeShellScript "poem-wallpaper-launch" ''
    size_file="''${XDG_STATE_HOME:-$HOME/.local/state}/poem-wallpaper/font-size"
    size=24
    if [[ -r "$size_file" ]]; then
      read -r saved_size < "$size_file"
      if [[ "$saved_size" =~ ^[0-9]+$ ]] && (( saved_size >= 12 && saved_size <= 72 )); then
        size="$saved_size"
      fi
    fi
    exec ${poemWallpaper}/bin/vertical-poem-wallpaper "$size"
  '';

  poemWallpaperSize = pkgs.writeShellApplication {
    name = "poem-wallpaper-size";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+$ ]] || (( $1 < 12 || $1 > 72 )); then
        echo "Usage: poem-wallpaper-size POINTS (12-72)" >&2
        exit 2
      fi

      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/poem-wallpaper"
      mkdir -p "$state_dir"
      printf '%s\n' "$1" > "$state_dir/font-size.tmp"
      mv "$state_dir/font-size.tmp" "$state_dir/font-size"
      systemctl --user restart poem-wallpaper.service
      echo "Poem wallpaper size set to $1pt"
    '';
  };
in
{
  config = lib.mkIf (osConfig.portable.role == "remote") {
    home.packages = [ poemWallpaperSize ];

    systemd.user.services.poem-wallpaper = {
      Unit = {
        Description = "Vertical Chinese poem wallpaper";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = poemWallpaperLauncher;
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };
  };
}
