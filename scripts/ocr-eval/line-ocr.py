#!/usr/bin/env python3
"""Line-level OCR for scanned poetry, via RapidOCR (ONNX PP-OCRv5 models).

Rationale: document-to-Markdown pipelines reflow text into paragraphs, which
destroys poetry. This does the opposite by construction -- it never joins
anything. Text detection yields one box per printed line; each box is
recognised independently; boxes are sorted by vertical position; and each box
is emitted as exactly one output line. Stanza breaks are recovered from the
vertical gap between consecutive boxes: a gap materially larger than the modal
line pitch on the page becomes a blank line.

Outputs, per input image:
  <stem>.<tag>.txt        raw text, one detected line per output line
  <stem>.<tag>.boxes.tsv  y_top, y_bottom, x_left, x_right, score, text

Usage: line-ocr.py --out DIR [--tag NAME] [--gap-ratio R] IMAGE [IMAGE ...]
"""
import argparse
import pathlib
import statistics
import sys
import time


def group_lines(items, y_tol_ratio=0.5):
    """Merge boxes that sit on the same printed line.

    The detector usually gives one box per line, but a wide inter-character gap
    (as in the spaced-out poem titles) can split one line into several boxes.
    Two boxes belong to the same line when their vertical centres are closer
    than y_tol_ratio of the median box height.
    """
    if not items:
        return []
    heights = [b[1] - b[0] for b in items] or [1]
    tol = max(1.0, statistics.median(heights) * y_tol_ratio)
    items = sorted(items, key=lambda b: (b[0] + b[1]) / 2)
    lines, cur = [], [items[0]]
    for it in items[1:]:
        cy = (it[0] + it[1]) / 2
        ref = statistics.mean([(c[0] + c[1]) / 2 for c in cur])
        if abs(cy - ref) <= tol:
            cur.append(it)
        else:
            lines.append(cur)
            cur = [it]
    lines.append(cur)
    return lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--tag", default="rapidocr")
    ap.add_argument(
        "--gap-ratio",
        type=float,
        default=1.6,
        help="blank line inserted when the gap between consecutive line "
        "baselines exceeds this multiple of the page's modal line pitch",
    )
    args = ap.parse_args()

    from rapidocr import RapidOCR

    engine = RapidOCR()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    for path in args.images:
        p = pathlib.Path(path)
        t0 = time.perf_counter()
        res = engine(str(p))
        elapsed = time.perf_counter() - t0

        boxes = getattr(res, "boxes", None)
        txts = getattr(res, "txts", None)
        scores = getattr(res, "scores", None)
        if boxes is None or txts is None:
            print(f"{p.name}: no text detected ({elapsed:.2f}s)", file=sys.stderr)
            (out / f"{p.stem}.{args.tag}.txt").write_text("", encoding="utf-8")
            continue

        items = []
        for box, txt, sc in zip(boxes, txts, scores):
            ys = [pt[1] for pt in box]
            xs = [pt[0] for pt in box]
            items.append((min(ys), max(ys), min(xs), max(xs), float(sc), txt))

        lines = group_lines(items)
        # Within a printed line, order the fragments left to right.
        rows = []
        for grp in lines:
            grp = sorted(grp, key=lambda b: b[2])
            rows.append(
                (
                    min(g[0] for g in grp),
                    max(g[1] for g in grp),
                    min(g[2] for g in grp),
                    max(g[3] for g in grp),
                    min(g[4] for g in grp),
                    # Join fragments with no separator: a split here is a
                    # detector artefact of wide letter-spacing, not a space.
                    "".join(g[5] for g in grp),
                )
            )

        # Stanza detection: compare each inter-line gap against the modal pitch.
        centres = [(r[0] + r[1]) / 2 for r in rows]
        pitches = [b - a for a, b in zip(centres, centres[1:])]
        pitch = statistics.median(pitches) if pitches else 0

        text_lines = []
        for i, r in enumerate(rows):
            if i and pitch and (centres[i] - centres[i - 1]) > pitch * args.gap_ratio:
                text_lines.append("")
            text_lines.append(r[5])

        (out / f"{p.stem}.{args.tag}.txt").write_text(
            "\n".join(text_lines) + "\n", encoding="utf-8"
        )
        with (out / f"{p.stem}.{args.tag}.boxes.tsv").open("w", encoding="utf-8") as fh:
            fh.write("y_top\ty_bot\tx_left\tx_right\tscore\ttext\n")
            for r in rows:
                fh.write(
                    f"{r[0]:.0f}\t{r[1]:.0f}\t{r[2]:.0f}\t{r[3]:.0f}\t{r[4]:.3f}\t{r[5]}\n"
                )
        print(f"{p.name}: {len(rows)} lines, pitch={pitch:.1f}px, {elapsed:.2f}s")


if __name__ == "__main__":
    main()
