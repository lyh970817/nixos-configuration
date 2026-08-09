#!/usr/bin/env python3
"""Compare poppler's and mupdf's JBIG2 decode of the same page images.

Both are read at native resolution (no rescaling), so any difference is a real
decoder disagreement: content one of them dropped or got wrong.

Usage: compare-native.py <native-dir>
"""
import pathlib
import sys

from PIL import Image, ImageChops

root = pathlib.Path(sys.argv[1])

print(f"{'page':>8} {'size':>14} {'black% pop':>11} {'black% mu':>10} {'diff px':>9}  verdict")
for m in sorted((root / "mupdf").glob("pg-*.png")):
    stem = m.stem
    cands = list((root / "poppler").glob(stem + "*.png"))
    if not cands:
        print(f"{stem:>8}  poppler output MISSING")
        continue
    a = Image.open(cands[0]).convert("1")
    b = Image.open(m).convert("1")
    if a.size != b.size:
        print(f"{stem:>8}  SIZE MISMATCH {a.size} vs {b.size}")
        continue
    total = a.size[0] * a.size[1]
    # PIL mode "1" histograms report counts at 0 (black) and 255 (white).
    ka = a.histogram()[0] / total * 100
    kb = b.histogram()[0] / total * 100
    diff = ImageChops.difference(a.convert("L"), b.convert("L"))
    nz = sum(c for v, c in enumerate(diff.histogram()) if v > 0)
    verdict = "IDENTICAL" if nz == 0 else "DIFFERENT"
    if nz:
        diff.save(root / "mupdf" / (stem + ".diff.png"))
    print(f"{stem:>8} {str(a.size):>14} {ka:>11.3f} {kb:>10.3f} {nz:>9}  {verdict}")
