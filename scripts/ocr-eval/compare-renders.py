#!/usr/bin/env python3
"""Compare poppler vs mupdf renders of the same pages pixel by pixel.

JBIG2 decoders can disagree; poppler warns "Unknown segment type in JBIG2
stream" on this file. If the two decoders produce different pixels, content is
being silently dropped or corrupted by one of them, and any extraction path
that trusts a single renderer is unsafe.

Usage: compare-renders.py <render-dir>
Expects <render-dir>/poppler/pg-NNN.png and <render-dir>/mupdf/pg-NNN.png.
Writes a diff image next to the mupdf render when pages differ.
"""
import sys
import pathlib

from PIL import Image, ImageChops

root = pathlib.Path(sys.argv[1])
pop = sorted((root / "poppler").glob("pg-*.png"))

print(f"{'page':>6} {'poppler':>14} {'mupdf':>14} {'diff px':>10} {'diff %':>8}  verdict")
for p in pop:
    m = root / "mupdf" / p.name
    if not m.exists():
        print(f"{p.stem:>6} {'-':>14} {'MISSING':>14}")
        continue
    a = Image.open(p).convert("L")
    b = Image.open(m).convert("L")
    if a.size != b.size:
        # Renderers can round page size differently; crop to the common area
        # so a 1px size difference does not masquerade as a content difference.
        w = min(a.size[0], b.size[0])
        h = min(a.size[1], b.size[1])
        a = a.crop((0, 0, w, h))
        b = b.crop((0, 0, w, h))
    diff = ImageChops.difference(a, b)
    # Ignore 1-level antialiasing noise; count only substantive differences.
    nz = sum(c for v, c in enumerate(diff.histogram()) if v > 16)
    total = a.size[0] * a.size[1]
    pct = 100.0 * nz / total
    verdict = "IDENTICAL" if nz == 0 else ("near-identical" if pct < 0.01 else "DIFFERENT")
    if nz:
        diff.point(lambda v: 255 - min(v * 4, 255)).save(
            root / "mupdf" / (p.stem + ".diff.png")
        )
    print(
        f"{p.stem:>6} {str(Image.open(p).size):>14} {str(Image.open(m).size):>14} "
        f"{nz:>10} {pct:>8.4f}  {verdict}"
    )
