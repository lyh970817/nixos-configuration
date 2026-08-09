#!/usr/bin/env python3
"""Find pages where one poem ends and the next begins.

A poem title is set centred, so its box centre sits near the page's horizontal
centre while body lines are flush left at a consistent margin. A page whose
*first* line is a title is just a poem opening; a page with a title that has
body lines above it is a true poem boundary, which is the interesting case for
evaluating how a tool marks titles and poem breaks.

Usage: find-boundaries.py <dir-of-boxes-tsv>
"""
import pathlib
import statistics
import sys

root = pathlib.Path(sys.argv[1])

for tsv in sorted(root.glob("*.boxes.tsv")):
    rows = []
    for line in tsv.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) < 6:
            continue
        rows.append(
            (int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]),
             float(parts[4]), parts[5])
        )
    if len(rows) < 4:
        continue
    lefts = [r[2] for r in rows]
    body_left = statistics.median(lefts)
    page_mid = statistics.median([(r[2] + r[3]) / 2 for r in rows])

    hits = []
    for i, r in enumerate(rows):
        centred = abs(((r[2] + r[3]) / 2) - page_mid) < 120
        indented = r[2] > body_left + 100
        short = (r[3] - r[2]) < 400
        if i > 0 and centred and indented and short:
            hits.append((i, r[5]))
    if hits:
        print(f"{tsv.name}: {hits}")
