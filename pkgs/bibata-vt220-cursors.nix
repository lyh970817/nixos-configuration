{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  clickgen,
  resvg,
  # Base (body) colour. Grey on purpose: the pointer is meant to read as a
  # plausible pointer on a battered modern Unix laptop, not as part of a VT220.
  # Green belongs in the details, not in the arrow.
  baseColor ? "#A8B0A8",
  # Outline colour. Near-black with just enough green in it to sit on the
  # phosphor background without looking like a foreign black.
  outlineColor ? "#101612",
  # Watch-background colour -- upstream's third customisable slot, and the only
  # one that carries phosphor green. It fills the disc behind the loading
  # spinner, so the accent shows up exactly where a loading indicator does.
  # The overlay in flake.nix binds this to the active palette's foreground rung
  # rather than to a literal, so a phosphor retune carries the cursor with it.
  accentColor ? "#4BAE55",
}:

# Bibata Original, rebuilt from the upstream SVG sources with custom colours.
#
# nixpkgs' bibata-cursors ships only the three fixed upstream variants (Amber,
# Classic, Ice), and their colours are baked into the released bitmaps.zip that
# derivation consumes -- there is no override that reaches them. Custom colours
# therefore mean re-rendering the SVGs, which upstream does with `cbmp`, a
# Node/Puppeteer tool that drives headless Chromium. That cannot run in a Nix
# sandbox (no network for the browser download, no sane way to run it offline),
# so this derivation replaces only that one step with resvg and keeps the rest
# of upstream's pipeline intact: the same SVG sources, the same colour
# placeholders, the same ctgen configs, the same hotspots.
#
# Substituting the renderer is safe, and was checked rather than assumed:
# recolouring the Original SVGs with the stock Ice values and rendering all 164
# of them at 256x256 with resvg reproduces upstream's own released
# bitmaps/Bibata-Original-Ice PNGs at RMSE 0 -- 164/164 pixel-identical,
# including the drop-shadow-filtered `wait` frames. resvg is a drop-in for the
# browser here, not an approximation.
#
# The three placeholders come from upstream's cbmp contract, documented in
# README.md ("Customize Colors") and used by render.json:
#
#   #00FF00 -> base colour     (-bc)
#   #0000FF -> outline colour  (-oc)
#   #FF0000 -> watch background (-wc), i.e. the loading-spinner disc
#
# Note #FE0000 also occurs upstream (the red slash in circle, crossed_circle,
# crosshair and dnd_no_drop). cbmp does not touch it and neither does this
# build, so that stays upstream red exactly as it does in stock Bibata.
#
# Only the left-handed "normal" Original set is built. Modern is deliberately
# not built: its rounded geometry is what the sharper-edged Original was chosen
# over.

let
  themeName = "Bibata-Original-VT220";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "bibata-vt220-cursors";
  # Tracks the upstream source revision the SVGs and hotspot configs come from,
  # which is also the version nixpkgs' bibata-cursors pins -- so the fetch is
  # already in the binary cache's fixed-output set.
  version = "2.0.7";

  src = fetchFromGitHub {
    owner = "ful1e5";
    repo = "Bibata_Cursor";
    rev = "v${finalAttrs.version}";
    hash = "sha256-kIKidw1vditpuxO1gVuZeUPdWBzkiksO/q2R/+DUdEc=";
  };

  nativeBuildInputs = [
    clickgen
    resvg
  ];

  # Reach the colours from the builder without re-quoting them in the script.
  inherit baseColor outlineColor accentColor;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    # svg/original is a directory of symlinks into svg/groups (see svg/link.py),
    # so -L is what makes the copy real and writable.
    mkdir -p svgwork bitmaps
    cp -rL svg/original/. svgwork/
    chmod -R u+w svgwork

    # Fail loudly if upstream ever changes the placeholder contract, rather
    # than shipping a theme silently rendered in cbmp's raw red/green/blue.
    for placeholder in '#00FF00' '#0000FF' '#FF0000'; do
      grep -RIqi -e "$placeholder" svgwork || {
        echo "bibata-vt220-cursors: placeholder $placeholder is absent from" >&2
        echo "svg/original; upstream changed the cbmp colour contract." >&2
        echo "Recheck render.json and README.md before bumping version." >&2
        exit 1
      }
    done

    find svgwork -name '*.svg' -print0 | xargs -0 sed -i \
      -e "s/#00FF00/$baseColor/gI" \
      -e "s/#0000FF/$outlineColor/gI" \
      -e "s/#FF0000/$accentColor/gI"

    if grep -RIn -i -e '#00FF00' -e '#0000FF' -e '#FF0000' svgwork; then
      echo "bibata-vt220-cursors: placeholder survived above; substitution" >&2
      echo "did not cover the whole tree." >&2
      exit 1
    fi

    # ctgen wants one flat directory of 256x256 PNGs whose names match the
    # `png` keys in the config; animation frames keep their -NN suffix and are
    # globbed there. Frame names are unique across the tree, so flattening the
    # two animated subdirectories into it is unambiguous.
    find svgwork -name '*.svg' | while read -r svg; do
      resvg -w 256 -h 256 "$svg" "bitmaps/$(basename "$svg" .svg).png"
    done

    # Hotspots live in upstream's own config, which is the whole reason to keep
    # ctgen instead of driving xcursorgen directly. out_dir there is relative
    # to the config file, so this writes ./themes.
    ctgen configs/normal/x.build.toml \
      -p x11 \
      -d "$PWD/bitmaps" \
      -n '${themeName}' \
      -c 'Grey and sharp edge Bibata XCursors with phosphor-green detail'

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -dm 0755 $out/share/icons
    cp -r 'themes/${themeName}' $out/share/icons/

    # A theme whose name does not resolve fails silently at runtime, so make an
    # empty or misnamed build a build failure instead.
    test -s "$out/share/icons/${themeName}/index.theme"
    test -s "$out/share/icons/${themeName}/cursors/left_ptr"

    runHook postInstall
  '';

  passthru = { inherit themeName; };

  meta = {
    description = "Bibata Original cursors in grey with VT220 phosphor-green detail";
    homepage = "https://github.com/ful1e5/Bibata_Cursor";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
})
