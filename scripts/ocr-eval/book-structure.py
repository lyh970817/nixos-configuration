#!/usr/bin/env python3
"""Summarise the book's structure from a whole-book line-level OCR pass.

Answers the questions that decide how a full conversion has to be organised:
how often a poem title appears part-way down a page (which would mean poem
boundaries do not line up with page boundaries), how reliably the running page
number can be stripped, and how often a poem continues across a page break.

Usage: book-structure.py <dir-of-boxes-tsv>
"""
import pathlib
import re
import statistics
import sys

root = pathlib.Path(sys.argv[1])

PAGENO = re.compile(r"^[·•.\s]*\d{1,3}[·•.\s]*$")

pages = {}
for tsv in sorted(root.glob("*.boxes.tsv")):
    num = int(re.search(r"pg-(\d+)", tsv.name).group(1))
    rows = []
    for line in tsv.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) >= 6:
            rows.append(
                (int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3]),
                 float(parts[4]), parts[5])
            )
    pages[num] = rows

mid_page_titles = []
pageno_ok = pageno_missing = 0
low_conf = 0
total_boxes = 0
empty_pages = []

for num, rows in sorted(pages.items()):
    total_boxes += len(rows)
    low_conf += sum(1 for r in rows if r[4] < 0.90)
    if not rows:
        empty_pages.append(num)
        continue
    if PAGENO.match(rows[-1][5]):
        pageno_ok += 1
    else:
        pageno_missing += 1

    body_left = statistics.median([r[2] for r in rows])
    page_mid = statistics.median([(r[2] + r[3]) / 2 for r in rows])
    for i, r in enumerate(rows[:-1]):
        if i == 0:
            continue
        centred = abs(((r[2] + r[3]) / 2) - page_mid) < 120
        indented = r[2] > body_left + 100
        short = (r[3] - r[2]) < 400
        if centred and indented and short and not PAGENO.match(r[5]):
            mid_page_titles.append((num, i, r[5]))

# A poem continues across a page break when a page's last body line does not
# end in a sentence-final mark and the following page does not open with a
# title. Approximated here by: page ends with a body line, next page's first
# line is flush left rather than centred.
spans = 0
starts = 0
for num, rows in sorted(pages.items()):
    nxt = pages.get(num + 1)
    if not rows or not nxt:
        continue
    body = [r for r in rows if not PAGENO.match(r[5])]
    nbody = [r for r in nxt if not PAGENO.match(r[5])]
    if not body or not nbody:
        continue
    nmid = statistics.median([(r[2] + r[3]) / 2 for r in nbody])
    nleft = statistics.median([r[2] for r in nbody])
    first = nbody[0]
    opens_with_title = (
        abs(((first[2] + first[3]) / 2) - nmid) < 150 and first[2] > nleft + 80
    )
    if opens_with_title:
        starts += 1
    elif len(body) > 3 and len(nbody) > 3:
        spans += 1

print(f"pages analysed              : {len(pages)}")
print(f"total detected line boxes   : {total_boxes}")
print(f"boxes below 0.90 confidence : {low_conf} ({100*low_conf/total_boxes:.2f}%)")
print(f"pages with no detected text : {len(empty_pages)} {empty_pages[:20]}")
print(f"last box is a page number   : {pageno_ok}")
print(f"last box is NOT a page number: {pageno_missing}")
print(f"pages whose next page opens with a centred title : {starts}")
print(f"pages that appear to continue onto the next page : {spans}")
print(f"mid-page centred short lines (candidate in-page poem starts): {len(mid_page_titles)}")
for m in mid_page_titles[:40]:
    print("   ", m)
