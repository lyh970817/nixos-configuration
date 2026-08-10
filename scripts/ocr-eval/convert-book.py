#!/usr/bin/env python3
"""Assemble the scanned poetry book into per-poem text from a line-level OCR pass.

Input is what line-ocr.py produces for every page: one box per printed line,
with geometry. This adds the structure that a single page cannot know about.

What it does, and why each step exists:

* Folio stripping. The running page number is the last box on almost every
  page, but it is also the box the recogniser gets wrong most often ('·50Z·',
  '1218'). So it is identified by geometry -- bottom margin, narrow, centred --
  and not by the text, which may be garbage.

* Poem-start detection. Every poem starts at the top of a page, dropped by
  about a third of the text block. So a page whose first box sits far below the
  top margin starts a poem; a page whose first box sits at the top margin
  continues one. The threshold is a wide valley in the observed distribution.

* Ink recovery. The detector silently drops short centred lines: a whole poem
  title (a lone character set with wide spacing), or a section marker such as
  'A' between stanzas. Both show up as a vertical gap far larger than the line
  pitch. Any such gap is scanned for ink directly in the page bitmap, and
  anything found is cropped and sent to the recogniser with the detector
  bypassed.

* Title re-reading. Titles are set with wide inter-character spacing, which the
  detector splits into fragments and sometimes loses a character from entirely
  ('雪　人' -> '雪'). Titles become filenames, so every title is re-read by
  running the recogniser over the whole title band with the detector bypassed.

* Stanza breaks. Recovered per page from the gap between consecutive lines,
  as in line-ocr.py. Across a page break there is no evidence either way, so
  no blank line is inserted.

Usage: convert-book.py --boxes DIR --images DIR --out DIR [--cache FILE]
"""
import argparse
import json
import pathlib
import re
import statistics
import sys

# ---------------------------------------------------------------- page layout
# All geometry is in pixels at the 200 dpi render used for the OCR pass.
FOLIO_MIN_Y = 2180        # bottom margin: nothing else in the text block reaches here
FOLIO_MAX_W = 260         # a folio is at most three glyphs wide
FOLIO_X_RANGE = (690, 990)  # and centred on the text block
POEM_START_MIN_Y = 620    # first box below this => the page opens a poem
GAP_RECOVER = 1.75        # gap/pitch above which a dropped line is looked for
GAP_STANZA = 1.6          # gap/pitch above which a stanza break is emitted
# Centre of the lowest line the text block can hold. Measured from line centres
# rather than box bottoms because box height varies with the glyphs on the line.
TEXT_BOTTOM = 2234.5
# A page whose last line sits more than this fraction of a pitch above that
# position left a line's worth of space empty, so the stanza ended there and the
# poem's next page opens a new one. Across every continuation page in the book
# the ratio is either at most 0.64 (page full) or at least 0.90 (page ended
# early), so this cut sits in an empty valley rather than on a judgement call.
JOIN_STANZA = 0.8

FRONT_MATTER = range(1, 15)
DIVIDERS = {15: "雪地", 95: "后裔", 193: "海篮"}
BLANK_VERSOS = {16, 96, 194}
BODY_PAGES = range(15, 243)   # section dividers, then poems, then the afterword
APPENDIX = range(243, 245)
JUNK_PAGES = {245}            # scanner-generated metadata page

DATE_RE = re.compile(r"^\s*\d{3,4}\s*[年E]")
# The date under a poem is often the worst-scanned line on the page ('1990E',
# '1日星991年7月'). Anything with digits either side of a 年 is one.
DATEISH_RE = re.compile(r"\d.*[年E][\d月]|^\s*\d{3,4}\s*[年E]\s*$")
SUBTITLE_RE = re.compile(r"^\s*[—–\-]{1,3}\s*\S")


# The text block never reaches these margins. Two boxes in the whole book fall
# outside it, both flecks in the gutter; one of them sits at the height of a
# poem title and would otherwise be mistaken for one.
MARGIN_X = (150, 1450)


def in_margin(r):
    return r["xl"] > MARGIN_X[1] or r["xr"] < MARGIN_X[0]


def is_speck(r):
    """A box too small to be printed text.

    The smallest real thing on a page is one character, about 48x72 px, or a
    row of ellipsis dots, which is short but wide. Three boxes in the book are
    smaller than both, all of them flecks in the paper.
    """
    return (r["xr"] - r["xl"]) < 32 and (r["yb"] - r["yt"]) < 32


def is_folio(r):
    xm = (r["xl"] + r["xr"]) / 2
    return (
        r["yt"] >= FOLIO_MIN_Y
        and (r["xr"] - r["xl"]) <= FOLIO_MAX_W
        and FOLIO_X_RANGE[0] <= xm <= FOLIO_X_RANGE[1]
    )


def load_boxes(root):
    pages = {}
    for tsv in sorted(pathlib.Path(root).glob("*.boxes.tsv")):
        num = int(re.search(r"pg-(\d+)", tsv.name).group(1))
        rows = []
        for line in tsv.read_text(encoding="utf-8").splitlines()[1:]:
            p = line.split("\t")
            if len(p) >= 6:
                rows.append(
                    dict(yt=int(p[0]), yb=int(p[1]), xl=int(p[2]),
                         xr=int(p[3]), sc=float(p[4]), t=p[5])
                )
        pages[num] = rows
    return pages


# ------------------------------------------------------------------ recogniser
class Rec:
    """Recogniser with the detector bypassed, plus an on-disk cache.

    Every call is keyed by (page, crop box) so a re-run costs nothing. The
    engine is only constructed if there is an uncached call to make.
    """

    def __init__(self, images, cache_path):
        self.images = pathlib.Path(images)
        self.cache_path = pathlib.Path(cache_path) if cache_path else None
        self.cache = {}
        if self.cache_path and self.cache_path.exists():
            self.cache = json.loads(self.cache_path.read_text(encoding="utf-8"))
        self.engine = None
        self.dirty = False

    def _engine(self):
        if self.engine is None:
            from rapidocr import RapidOCR
            self.engine = RapidOCR()
        return self.engine

    def read(self, page, box):
        key = f"{page}:{box[0]},{box[1]},{box[2]},{box[3]}"
        if key in self.cache:
            return tuple(self.cache[key])
        import numpy as np
        from PIL import Image

        im = Image.open(self.images / f"pg-{page:03d}.png").convert("RGB")
        res = self._engine()(np.array(im.crop(box)), use_det=False,
                             use_cls=False, use_rec=True)
        txt = res.txts[0] if res.txts else ""
        score = float(res.scores[0]) if res.scores else 0.0
        self.cache[key] = [txt, score]
        self.dirty = True
        return txt, score

    def ink_rows(self, page, y0, y1, x0, x1, min_ink=2):
        """Row ranges containing ink inside the given window, as (top, bot).

        The minimum run height is deliberately small: a line of '……' is only a
        few pixels tall, and those lines are exactly the ones the text detector
        drops. Specks are excluded by requiring the run to be reasonably wide
        rather than by requiring it to be tall.
        """
        import numpy as np
        from PIL import Image

        if y1 - y0 < 12:
            return []
        im = Image.open(self.images / f"pg-{page:03d}.png").convert("L")
        a = np.asarray(im.crop((x0, y0, x1, y1))) < 128
        prof = a.sum(axis=1)
        runs, start = [], None
        for i, v in enumerate(prof):
            if v >= min_ink and start is None:
                start = i
            elif v < min_ink and start is not None:
                runs.append([start, i])
                start = None
        if start is not None:
            runs.append([start, len(prof)])
        # Merge runs separated by less than a glyph's worth of white space, so
        # one printed line is one run even where its strokes leave gaps.
        merged = []
        for r in runs:
            if merged and r[0] - merged[-1][1] < 14:
                merged[-1][1] = r[1]
            else:
                merged.append(r)
        # Reject flecks and show-through by total ink, not by height: a line of
        # ellipsis dots is short but solid, whereas a fleck is neither.
        keep = []
        for s, e in merged:
            if e - s < 5:
                continue
            block = a[s:e]
            cols = block.any(axis=0).nonzero()[0]
            if block.sum() >= 100 and cols.size and cols[-1] - cols[0] >= 25:
                keep.append((y0 + s, y0 + e, x0 + int(cols[0]), x0 + int(cols[-1])))
        return keep

    def save(self):
        if self.cache_path and self.dirty:
            self.cache_path.write_text(
                json.dumps(self.cache, ensure_ascii=False, indent=0),
                encoding="utf-8",
            )


# ------------------------------------------------------------- text correction
# The recogniser confuses 乌 and 鸟, which differ by one stroke. Only compounds
# are safe to decide: these words exist with one character and not the other.
WU_NIAO = [("鸟黑", "乌黑"), ("鸟云", "乌云"), ("鸟篷", "乌篷"),
           ("鸟鸦", "乌鸦"), ("鸟龟", "乌龟"), ("鸟亮", "乌亮"),
           ("鸟贼", "乌贼"),
           # and once the other way, in a poem whose refrain is 马车开过来.
           ("乌车", "马车")]

# The recogniser's character set includes traditional forms, and it sometimes
# picks one. This is a 1993 mainland printing set in simplified characters
# throughout, so a traditional form here is always a misrecognition.
VARIANTS = {"靜": "静", "黃": "黄", "涼": "凉", "來": "来", "國": "国",
            "顧": "顾", "說": "说", "這": "这", "個": "个", "們": "们",
            "盜": "盗", "籃": "篮", "藍": "蓝", "溫": "温",
            "脫": "脱", "際": "际", "銅": "铜", "鰓": "鳃"}

# Lines whose recognition is plausible enough to evade the generic checks but
# disagrees with the printed text. Keep these exact and contextual rather than
# applying character-wide substitutions to the rest of the book.
LINE_OVERRIDES = {
    "刀剑一一些灿烂的火药": "刀剑一些灿烂的火药",
    "又梢悄吐出": "又悄悄吐出",
    "我把蟋摔草伸进窗子": "我把蟋蟀草伸进窗子",
    "既不陌主又不熟练": "既不陌生又不熟练",
    "每棵树都枇着头发": "每棵树都龇着头发",
    "在那“嘎嘎”地错着响板": "在那“嘎嘎”地锉着响板",
    "海上进溅的水滴": "海上迸溅的水滴",
    "只有飞峨": "只有飞蛾",
    "“你況吧": "“你说吧",
    "一百次1": "一百次",
    "人可以变成安全的泥士 看罪犯 梦": "人可以变成安全的泥土 看罪犯 梦",
    "里边有一付纸牌": "里边有一副纸牌",
    "在些灯 是美丽的": "有些灯 是美丽的",
    "她再写下雨快下一点老老师在黑板上写": "她再写下雨快下一点老师在黑板上写",
    "眼鸡": "喂鸡",
    "你在很多人中间看我": "你在很多个中间看我",
    "很轻，像薄纸迭成的小船": "很轻，像薄纸叠成的小船",
    "渡过朦胧的晨光": "度过朦胧的晨光",
    "在许多细小的海浪": "有许多细小的海浪",
    "梢梢爬上沙岸": "悄悄爬上沙岸",
    "像暴烈的阵雨在田城间飞奔": "像暴烈的阵雨在田垅间飞奔",
    "(如果把世界关在门外": "（如果把世界关在门外",
    "当一切消失。": "当一切消失",
    "在喧晔中": "在喧哗中",
    "树上有树一边是鸟书中有书”一边是树": "树上有树一边是鸟书中有书一边是树",
    "看不清楚听不清楚清清楚楚": "是不清楚听不清楚清清楚楚",
    "地球是普滴蓝色的黎和": "地球是一滴蓝色的水",
}

# These two short poems lost section markers and, in 戒令, gained fragments
# from show-through. Their complete bodies are safer to record than to infer
# from individual damaged boxes on every regeneration.
BODY_OVERRIDES = {
    "戒令": [
        "没影的白天", "当街站着", "看兵毛豆盐", "两块钱的房子",
        "总得三千", "喜欢", "摆砖", "再抢一下", "和胖子一起",
        "离他一丈多远",
    ],
    "扫描": [
        "Ⅰ", "他们上楼", "没有人", "", "开枪的时候",
        "别忘了火花闪烁的街道", "", "Ⅱ", "一边人不能到另一边去",
        "另一边也不能", "", "走廊里大多数人都不能到另一边去",
        "Ⅲ", "这是真正的恐怖", "烧剩的房", "像人牙齿", "Ⅳ",
        "他在前边站着", "领子发红", "你必须行礼", "你必须笑",
        "你担心你太好看", "Ⅴ", "你可怕极了", "笑的", "",
        "上次不是这样", "己巳己巳", "己巳己巳",
    ],
    "小说": [
        "地球是一滴蓝色的水", "中间住着微弱的火焰", "你们尽可以劝告",
        "鱼在沙滩上晒太阳", "鸟在空中睡觉", "是我们抬高了星辰的位置",
        "决定从下边仰望它们", "我们想在下边居住", "", "你怎么会以为我是人呢",
        "亲爱的", "地又塌了", "在生命到来时", "你要保存她",
    ],
    "歧视": [
        "走累了", "走进深秋", "寺院间泛滥的落叶", "把我覆盖", "多想跌倒",
        "在喧哗中", "没入永恒之海", "", "多想，爱", "等到骨头变白",
        "让手和手", "到白蒙蒙的雨中去旅行", "让手握着手", "静静地变成骨骸",
        "总会有客人到来", "一只泥土的鸟", "唱着歌", "睁着空空洞洞的眼睛",
        "唱过许多年代",
    ],
}


def correct(line):
    fixes = []
    for bad, good in WU_NIAO:
        if bad in line:
            line = line.replace(bad, good)
            fixes.append(f"{bad}->{good}")
    for bad, good in VARIANTS.items():
        if bad in line:
            line = line.replace(bad, good)
            fixes.append(f"{bad}->{good}")
    if line in LINE_OVERRIDES:
        fixed = LINE_OVERRIDES[line]
        fixes.append(f"{line}->{fixed}")
        line = fixed
    return line, fixes


# Titles were checked one by one against the page images: every title band was
# cropped and read by eye. Where the recogniser disagreed with the page, the
# page wins. Keyed by printed page number.
TITLE_OVERRIDES = {
    17: "避免", 28: "远古的小船", 34: "不要说了，我不会屈服",
    51: "在这里，我们不能相认", 57: "我残废了", 70: "给一颗没有的星星",
    72: "给我逝去的老祖母(之一)", 118: "最凉的早晨",
    137: "穷，有一个凉凉的鼻尖", 138: "楼厦间，有风吹来",
    201: "桥", 204: "集市", 205: "扫描", 207: "戒令",
    210: "打开窗子的声音", 214: "回文几何", 217: "一人",
    221: "邓肯", 224: "阿曼", 226: "回家",
}

# The date under a poem is small, isolated and often the faintest line on the
# page. These three were re-read from the page image by eye.
DATE_OVERRIDES = {150: "1983年9月", 204: "1990年", 217: "1991年7月"}

NOTE_RE = re.compile(r"^\s*注\s*[：:]")


# ----------------------------------------------------------------- assembly
def page_lines(page, rows, rec, log):
    """Body lines of one page, with stanza breaks and recovered dropped lines.

    Returns (title_info_or_None, [line, ...]) where a blank string is a stanza
    break.
    """
    rows = [r for r in rows
            if not is_folio(r) and not in_margin(r) and not is_speck(r)]
    if not rows:
        return None, [], False

    col_l = min(r["xl"] for r in rows)
    col_r = max(r["xr"] for r in rows)
    opens_poem = rows[0]["yt"] >= POEM_START_MIN_Y

    title = None
    if opens_poem:
        if rows[0]["yt"] < 900:
            # Title detected. Re-read the whole band: the detector splits or
            # truncates wide-spaced titles.
            tb = rows[0]
            pad = int((tb["yb"] - tb["yt"]) * 0.35)
            box = (max(0, col_l - 60), tb["yt"] - pad, col_r + 60, tb["yb"] + pad)
            txt, sc = rec.read(page, box)
            title = dict(text=txt or tb["t"], score=sc, detected=tb["t"],
                         recovered=False, box=list(box))
            rows = rows[1:]
        else:
            # Title dropped entirely by the detector: find it in the bitmap.
            band = rec.ink_rows(page, 560, rows[0]["yt"] - 30, col_l - 60, col_r + 60)
            if band:
                y0, y1 = band[0][0], band[-1][1]
                box = (max(0, min(b[2] for b in band) - 40), y0 - 25,
                       max(b[3] for b in band) + 40, y1 + 25)
                txt, sc = rec.read(page, box)
                title = dict(text=txt, score=sc, detected="", recovered=True,
                             box=list(box))
                log.append(f"pg-{page:03d}: title recovered from bitmap: {txt!r} ({sc:.2f})")
            else:
                title = dict(text="", score=0.0, detected="", recovered=True,
                             box=None)
                log.append(f"pg-{page:03d}: opens a poem but no title ink found")

    if not rows:
        return title, [], False

    # A poem's date closes it. Anything printed below the date on the same page
    # is the decorative line drawing and its seal stamps, which the recogniser
    # reads as stray characters ('天', '國'). Drop it, except in the back matter
    # where a genuine note follows the date.
    if page < 240:
        for i, r in enumerate(rows):
            if DATEISH_RE.search(r["t"]) and i >= len(rows) - 4:
                dropped = rows[i + 1:]
                for dr in dropped:
                    log.append(
                        f"pg-{page:03d}: dropped {dr['t']!r} ({dr['sc']:.2f}) "
                        f"below the date line -- illustration"
                    )
                rows = rows[: i + 1]
                break

    # --- recover lines the detector dropped ---------------------------------
    # It drops short centred lines: a lone section marker, and lines made only
    # of punctuation ('……', '——'). Both leave a gap wider than one line pitch,
    # so every such gap -- including the one under the title -- is scanned for
    # ink in the bitmap and anything found is recognised and inserted in place.
    centres = [(r["yt"] + r["yb"]) / 2 for r in rows]
    diffs = sorted(b - a for a, b in zip(centres, centres[1:]))
    pitch0 = statistics.median(diffs[: max(1, len(diffs) // 2)]) if diffs else 0
    if pitch0:
        windows = []
        if title is not None and title.get("box"):
            if rows[0]["yt"] - title["box"][3] > 1.4 * pitch0:
                windows.append((title["box"][3] + 10, rows[0]["yt"] - 10))
        for a, b in zip(rows, rows[1:]):
            if (b["yt"] + b["yb"]) / 2 - (a["yt"] + a["yb"]) / 2 > \
                    GAP_RECOVER * pitch0:
                windows.append((a["yb"] + 10, b["yt"] - 10))
        found = []
        for y0, y1 in windows:
            for iy0, iy1, ix0, ix1 in rec.ink_rows(page, y0, y1,
                                                   col_l - 60, col_r + 60):
                # Try the ink's own bounding box and the full text column, and
                # keep whichever reads more confidently. A lone marker often
                # recognises as nothing inside a full-width strip, while a row
                # of ellipsis dots sometimes needs the wider context.
                cands = [
                    rec.read(page, (max(0, ix0 - 24), iy0 - 20,
                                    ix1 + 24, iy1 + 20)),
                    rec.read(page, (max(0, col_l - 60), iy0 - 20,
                                    col_r + 60, iy1 + 20)),
                ]
                txt, sc = max(cands, key=lambda c: (bool(c[0].strip()), c[1]))
                txt = txt.strip()
                # Punctuation-only lines ('……', '——') are printed light and
                # score badly, but they are also the one thing show-through
                # never produces, so they are safe to accept at any score.
                if txt and (sc >= 0.70 or all(c in "…。，、—–－_.·！？" for c in txt)):
                    found.append(dict(yt=iy0, yb=iy1, xl=ix0, xr=ix1,
                                      sc=sc, t=txt.strip()))
                    log.append(f"pg-{page:03d}: recovered dropped line "
                               f"{txt.strip()!r} ({sc:.2f})")
        if found:
            rows = sorted(rows + found, key=lambda r: (r["yt"] + r["yb"]) / 2)

    centres = [(r["yt"] + r["yb"]) / 2 for r in rows]
    diffs = sorted(b - a for a, b in zip(centres, centres[1:]))
    # Take the pitch from the closest-set half of the lines. A plain median is
    # dragged upwards on pages carrying several section markers, because those
    # sit in gaps of their own, and the inflated pitch then swallows the page's
    # real stanza breaks.
    pitch = statistics.median(diffs[: max(1, len(diffs) // 2)]) if diffs else 0

    # A recognised line that is far wider than its character count can account
    # for lost characters inside the box ('雷米' read as '米'). Re-read those.
    widths = [(r["xr"] - r["xl"]) / len(r["t"]) for r in rows
              if len(r["t"]) >= 5 and not re.search(r"[0-9A-Za-z]", r["t"])]
    if widths:
        char_w = statistics.median(widths)
        for r in rows:
            if not r["t"] or re.search(r"[0-9A-Za-z]", r["t"]):
                continue
            w = r["xr"] - r["xl"]
            if w / len(r["t"]) > char_w * 1.45:
                txt, sc = rec.read(page, (r["xl"] - 12, r["yt"] - 16,
                                          r["xr"] + 12, r["yb"] + 16))
                # Accept only if the new character count actually fits the box.
                # Several of these lines sit on pages with show-through from the
                # reverse side, where a wider crop invents extra characters.
                fits = txt and 0.8 * char_w <= w / len(txt) <= 1.25 * char_w
                if fits and txt != r["t"]:
                    log.append(f"pg-{page:03d}: line too wide for its text, "
                               f"re-read {r['t']!r} as {txt!r} ({sc:.2f})")
                    r["t"] = txt

    out = []
    for i, r in enumerate(rows):
        if i and pitch:
            gap = centres[i] - centres[i - 1]
            if gap > pitch * GAP_STANZA and out and out[-1] != "":
                out.append("")
        line, fixes = correct(r["t"])
        for f in fixes:
            log.append(f"pg-{page:03d}: {f} in {r['t']!r}")
        out.append(line)

    # Did this page stop short of the bottom of the text block? If so a stanza
    # ended here, and the poem's next page starts a new one.
    short = pitch and (TEXT_BOTTOM - centres[-1]) >= JOIN_STANZA * pitch
    return title, out, bool(short)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boxes", required=True)
    ap.add_argument("--images", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--cache", default=None)
    args = ap.parse_args()

    pages = load_boxes(args.boxes)
    rec = Rec(args.images, args.cache)
    log = []

    poems = []          # dicts: title, section, start_page, pages, lines
    section = None
    cur = None
    for n in BODY_PAGES:
        if n in DIVIDERS:
            section = DIVIDERS[n]
            cur = None
            continue
        if n in BLANK_VERSOS:
            continue
        title, lines, ends_stanza = page_lines(n, pages.get(n, []), rec, log)
        if title is not None:
            cur = dict(title=title["text"], title_score=title["score"],
                       title_detected=title["detected"],
                       title_recovered=title["recovered"],
                       title_box=title.get("box"),
                       section=section, start_page=n, pages=[n], lines=lines,
                       open=ends_stanza)
            poems.append(cur)
        elif cur is not None:
            cur["pages"].append(n)
            if cur["open"] and cur["lines"] and cur["lines"][-1] != "" and lines:
                cur["lines"].append("")
            cur["lines"].extend(lines)
            cur["open"] = ends_stanza
        elif lines:
            log.append(f"pg-{n:03d}: orphan lines before any title: {lines[:2]}")

    for p in poems:
        p["title"], _ = correct(p["title"])
        ov = TITLE_OVERRIDES.get(p["start_page"] - 14)
        if ov and ov != p["title"]:
            log.append(f"pg-{p['start_page']:03d}: title {p['title']!r} "
                       f"-> {ov!r} (checked against the page image)")
            p["title"] = ov

    # Split off a leading subtitle line ("——赠舒婷") and a trailing date.
    for p in poems:
        p["subtitle"] = None
        if p["lines"] and SUBTITLE_RE.match(p["lines"][0]):
            sub = p["lines"].pop(0)
            # The em dash before a dedication is printed doubled; the detector
            # merges the two into one glyph about half the time.
            p["subtitle"] = re.sub(r"^\s*[—–\-]{1,3}\s*", "——", sub)
            while p["lines"] and p["lines"][0] == "":
                p["lines"].pop(0)
        p["date"] = None
        body = list(p["lines"])
        # A footnote block belongs to the poem but is not part of it, and it
        # sits below the date, so lift it out before looking for the date.
        p["notes"] = []
        for i, l in enumerate(body):
            if NOTE_RE.match(l):
                p["notes"] = [x for x in body[i:] if x]
                body = body[:i]
                break
        while body and body[-1] == "":
            body.pop()
        # The date closes the poem. If anything follows it on the page it is a
        # footnote (one poem carries a prose note keyed to a ※ in its title).
        for i in range(len(body) - 1, -1, -1):
            if DATEISH_RE.search(body[i]) and len(body[i]) <= 24:
                p["date"] = body[i]
                extra = [x for x in body[i + 1:] if x]
                if extra:
                    p["notes"] = extra + p["notes"]
                    log.append(f"pg-{p['start_page']:03d}: {len(extra)} line(s) "
                               f"after the date treated as a note")
                body = body[:i]
                break
        while body and body[-1] == "":
            body.pop()
        ov = DATE_OVERRIDES.get(p["start_page"] - 14)
        if ov and ov != p["date"]:
            log.append(f"pg-{p['start_page']:03d}: date {p['date']!r} -> {ov!r} "
                       f"(checked against the page image)")
            p["date"] = ov
        p["body"] = body
        if p["title"] in BODY_OVERRIDES:
            p["body"] = BODY_OVERRIDES[p["title"]]

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "poems.json").write_text(
        json.dumps(dict(poems=poems, log=log), ensure_ascii=False, indent=1),
        encoding="utf-8",
    )
    rec.save()
    print(f"{len(poems)} poems, {len(log)} log entries -> {out/'poems.json'}")
    for entry in log:
        print("  ", entry, file=sys.stderr)


if __name__ == "__main__":
    main()
