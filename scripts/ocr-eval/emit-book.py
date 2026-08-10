#!/usr/bin/env python3
"""Write the converted book out: one Markdown file, one file per poem, and the
short poems used by the fastfetch welcome banner.

Verse is emitted one printed line per output line and nothing is re-wrapped;
that fidelity is the whole point of the conversion. Prose in the front matter
is the opposite case -- there the printed line breaks are an artefact of a
narrow column, so paragraphs are rejoined, using the first-line indent that the
typesetter used to mark them.

The table of contents is rebuilt from the poems themselves rather than read off
the contents pages: those pages set two-character titles with wide spacing and
run dot leaders into them, which no OCR pass here read reliably.

Usage: emit-book.py --poems poems.json --boxes DIR --book DIR --short DIR
                    [--short-max 36]
"""
import argparse
import json
import pathlib
import re
import shutil
import statistics

PAGE_OFFSET = 14   # PDF page number minus printed page number


def load_page(boxes_dir, n):
    f = pathlib.Path(boxes_dir) / f"pg-{n:03d}.rapidocr.boxes.tsv"
    rows = []
    for line in f.read_text(encoding="utf-8").splitlines()[1:]:
        p = line.split("\t")
        if len(p) >= 6:
            rows.append(dict(yt=int(p[0]), yb=int(p[1]), xl=int(p[2]),
                             xr=int(p[3]), sc=float(p[4]), t=p[5]))
    return rows


def reflow(rows, skip=0):
    """Rejoin a narrow prose column into paragraphs.

    A paragraph's first line is indented, so any line starting materially to
    the right of the column's left edge opens a new one.
    """
    rows = rows[skip:]
    if not rows:
        return []
    left = statistics.median([r["xl"] for r in rows])
    paras, cur = [], []
    for r in rows:
        if cur and r["xl"] > left + 45:
            paras.append("".join(cur))
            cur = []
        cur.append(r["t"])
    if cur:
        paras.append("".join(cur))
    return paras


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--poems", required=True)
    ap.add_argument("--boxes", required=True)
    ap.add_argument("--book", required=True)
    ap.add_argument("--short", required=True)
    ap.add_argument("--short-max", type=int, default=36)
    args = ap.parse_args()

    data = json.loads(pathlib.Path(args.poems).read_text(encoding="utf-8"))
    poems = data["poems"]

    book = pathlib.Path(args.book)
    per_poem = book / "poems"
    if per_poem.exists():
        shutil.rmtree(per_poem)
    per_poem.mkdir(parents=True)

    # ------------------------------------------------------------ front matter
    bio = reflow(load_page(args.boxes, 7), skip=1)
    colophon = [r["t"] for r in load_page(args.boxes, 4)]

    out = ["# 海篮", "", "顾城新诗自选集", "",
           "百花文艺出版社，1993年12月第1版。", "",
           "本文件由该书的扫描件经逐行 OCR 转换而成，每一印刷行对应一输出行，"
           "分节空行按版面行距还原。", "", "## 关于顾城", ""]
    out += [p for para in bio for p in (para, "")]

    out += ["## 目录", "",
            "原书目录页的点线与宽字距使 OCR 无法可靠识别，此目录由正文各诗"
            "的标题与页码重建。", ""]
    section = object()
    for p in poems:
        if p["section"] != section:
            section = p["section"]
            out += ["", f"### {section}", ""]
        out.append(f"- {p['title']} …… {p['start_page'] - PAGE_OFFSET}")
    out.append("")

    # ------------------------------------------------------------------- poems
    section = object()
    seen = {}
    for p in poems:
        if p["section"] != section:
            section = p["section"]
            out += ["", f"## {section}", ""]
        printed = p["start_page"] - PAGE_OFFSET
        chunk = [f"### {p['title']}", ""]
        if p["subtitle"]:
            chunk += [p["subtitle"], ""]
        chunk += p["body"]
        if p["date"]:
            chunk += ["", p["date"]]
        if p["notes"]:
            chunk += [""] + [f"> {n}" for n in p["notes"]]
        chunk.append("")
        out += chunk

        # One file per poem, titled by its heading.
        stem = p["title"]
        if stem in seen:
            seen[stem] += 1
            stem = f"{stem}（{seen[stem]}）"
        else:
            seen[stem] = 1
        single = [f"# {p['title']}", ""]
        if p["subtitle"]:
            single += [p["subtitle"], ""]
        single += p["body"]
        if p["date"]:
            single += ["", p["date"]]
        if p["notes"]:
            single += [""] + [f"> {n}" for n in p["notes"]]
        single += ["", f"—— 《海篮》第 {printed} 页"]
        (per_poem / f"{stem}.md").write_text(
            "\n".join(single) + "\n", encoding="utf-8")

    # -------------------------------------------------------------- back matter
    appendix = []
    for n in (243, 244):
        for r in load_page(args.boxes, n):
            t = r["t"]
            if re.fullmatch(r"[\s·•.,、]*[0-9OolI]{1,3}[\s·•.,、]*", t):
                continue   # folio
            if t in ("附录：", "顾城自选代表作目录"):
                continue   # emitted as the heading below
            appendix.append(t)
    out += ["", "## 附录：顾城自选代表作目录", "",
            "这两页是小号字加点线的书目，OCR 结果不可靠，以下为原始识别结果，"
            "篇名与年月均有错讹，仅供参照。", ""] + appendix + [""]

    book.mkdir(parents=True, exist_ok=True)
    (book / "海篮.md").write_text("\n".join(out) + "\n", encoding="utf-8")

    # -------------------------------------------------------- the short poems
    short = pathlib.Path(args.short)
    if short.exists():
        for f in short.glob("*.txt"):
            f.unlink()
    short.mkdir(parents=True, exist_ok=True)
    picked = []
    for p in poems:
        if len(p["body"]) <= args.short_max and p["body"]:
            (short / f"{p['title']}.txt").write_text(
                "\n".join(p["body"]) + "\n", encoding="utf-8")
            picked.append((p["title"], len(p["body"])))
    print(f"{len(poems)} poems written to {book}")
    print(f"{len(picked)} of them are <= {args.short_max} body lines -> {short}")


if __name__ == "__main__":
    main()
