#!/usr/bin/env python3
"""Re-read a poem title by running recognition on the whole title band.

Poem titles are centred and set with wide inter-character spacing (就　义).
The text detector treats that gap as a word break, so it may emit one box per
character, drop a character entirely, or -- on contents pages, where the first
characters of several entries line up -- stitch characters from different lines
into one vertical box. Any of those corrupts the title, which matters because
titles become filenames.

The fix is to stop asking the detector to decide. Take the y range of the first
detected line, widen it to the full text column, and run the recogniser alone
on that crop, so the whole title is read as a single sequence.

Usage: title-band.py <page.png> <boxes.tsv> [line-index]
"""
import sys

import numpy as np
from PIL import Image
from rapidocr import RapidOCR

page, tsv = sys.argv[1], sys.argv[2]
idx = int(sys.argv[3]) if len(sys.argv) > 3 else 0

rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8")][1:]
y0, y1, x0, x1 = (int(v) for v in rows[idx][:4])

# Widen to the text column: use the leftmost and rightmost extents seen
# anywhere on the page, so a title whose outer characters were never detected
# is still inside the crop.
all_left = min(int(r[2]) for r in rows)
all_right = max(int(r[3]) for r in rows)

im = Image.open(page).convert("RGB")
pad_y = int((y1 - y0) * 0.35)
crop = im.crop(
    (
        max(0, all_left - 40),
        max(0, y0 - pad_y),
        min(im.width, all_right + 40),
        min(im.height, y1 + pad_y),
    )
)

engine = RapidOCR()
res = engine(np.array(crop), use_det=False, use_cls=False, use_rec=True)
print(f"detector said : {rows[idx][5]!r}")
print(f"band recognise: {res.txts!r}  scores={res.scores!r}")
