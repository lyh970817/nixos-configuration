{
  lib,
  stdenvNoCC,
  gtk3,
}:

# Matrix-Icons: the green icon set that pairs with the VT220-Amber GTK theme in
# dark mode. Vendored under assets/icons because it is not in nixpkgs, and
# because it is a local derivative rather than a redistributable upstream --
# it descends from truegav/hacker-theme's Matrix-2.0-S, but only 828 of its
# 25362 shared icons still match upstream byte for byte, so it cannot be
# refetched without losing the local artwork.
#
# The vendored tree is stored symlink-deduplicated (see
# scripts/icon-theme-relink.py), so the only real fix here is index.theme: it
# ships no Inherits key, so any name the theme lacks resolves against hicolor
# alone and renders as a missing-image placeholder. Adwaita is the fallback
# because its symbolic icons are recoloured to the GTK foreground and stay
# green; HighContrast's raster icons would come through white and reintroduce
# the mismatch this package exists to fix.
#
# The gtk-update-icon-cache call is kept as a build-time validity check, not to
# ship a cache. It parses index.theme and every directory it names, so a
# malformed theme fails the build here rather than silently degrading at
# runtime. nixpkgs then deletes the result in its own dropIconThemeCache phase,
# because caches belong to the profile rather than to a package; the profile
# regenerates one, which is where the caches next to Adwaita and HighContrast
# in /etc/profiles/per-user come from.
stdenvNoCC.mkDerivation {
  pname = "matrix-icons";
  version = "0-unstable-2026-08-07";

  src = ../assets/icons/Matrix-Icons;

  nativeBuildInputs = [ gtk3 ];

  # src is a plain directory, so there is nothing to unpack and no sourceRoot.
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dst="$out/share/icons/Matrix-Icons"
    mkdir -p "$dst"
    # -a keeps the deduplicating symlinks as symlinks; they are all relative
    # and stay inside the theme, so the copy remains self-contained.
    cp -a "$src"/. "$dst"
    chmod -R u+w "$dst"

    rm -f "$dst/icon-theme.cache"

    grep -q '^Inherits=' "$dst/index.theme" ||
      sed -i '/^\[Icon Theme\]$/a Inherits=Adwaita,hicolor' "$dst/index.theme"

    gtk-update-icon-cache --force "$dst"

    runHook postInstall
  '';

  meta = {
    description = "Green icon theme matching the VT220-Amber GTK theme";
    platforms = lib.platforms.linux;
  };
}
