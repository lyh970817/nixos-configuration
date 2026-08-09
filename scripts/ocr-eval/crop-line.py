#!/usr/bin/env python3
"""Crop one detected line out of a page image, using the box TSV that
line-ocr.py writes, and scale it up for visual inspection.

Used to check characters that OCR reports as "wrong but plausible" -- the
signature of a lossy JBIG2 symbol substitution, which no amount of OCR quality
would fix because the corruption is already in the decoded bitmap.

Usage: crop-line.py <page.png> <boxes.tsv> <line-index> <out.png> [scale]
"""
import sys

from PIL import Image

page, tsv, idx, out = sys.argv[1:5]
scale = int(sys.argv[5]) if len(sys.argv) > 5 else 3

rows = [l.rstrip("\n").split("\t") for l in open(tsv, encoding="utf-8")][1:]
y0, y1, x0, x1 = (int(v) for v in rows[int(idx)][:4])
pad = 10
im = Image.open(page).crop((max(0, x0 - pad), max(0, y0 - pad), x1 + pad, y1 + pad))
im.resize((im.width * scale, im.height * scale), Image.LANCZOS).save(out)
print(f"line {idx}: {rows[int(idx)][5]}  -> {out}")
