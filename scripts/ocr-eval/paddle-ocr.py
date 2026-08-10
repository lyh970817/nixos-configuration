#!/usr/bin/env python3
"""Run PaddleOCR two ways on the same pages, to separate the model's accuracy
from the pipeline's layout behaviour.

  --mode line       raw PP-OCRv5 detection + recognition. One detected box per
                    printed line; we sort by y and emit one output line each.
                    Nothing is ever joined, so line structure is preserved by
                    construction.
  --mode structure  the packaged PP-StructureV3 document pipeline, which emits
                    Markdown. This is the control: it shows what a
                    document-to-Markdown tool does to verse.

Usage: paddle-ocr.py --mode {line,structure} --out DIR IMAGE [IMAGE ...]
"""
import argparse
import pathlib
import statistics
import time


def emit_line_mode(images, out, gap_ratio):
    from paddleocr import PaddleOCR

    # enable_mkldnn=False is required: paddlepaddle 3.3.1's oneDNN path dies
    # with "ConvertPirAttribute2RuntimeAttribute not support
    # [pir::ArrayAttribute<pir::DoubleAttribute>]" on the PP-OCRv5 detector.
    ocr = PaddleOCR(
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
        lang="ch",
        enable_mkldnn=False,
    )
    for path in images:
        p = pathlib.Path(path)
        t0 = time.perf_counter()
        results = ocr.predict(str(p))
        elapsed = time.perf_counter() - t0

        rows = []
        for res in results:
            texts = res["rec_texts"]
            polys = res["rec_polys"]
            scores = res["rec_scores"]
            for poly, txt, sc in zip(polys, texts, scores):
                ys = [pt[1] for pt in poly]
                xs = [pt[0] for pt in poly]
                rows.append((min(ys), max(ys), min(xs), max(xs), float(sc), txt))
        rows.sort(key=lambda r: (r[0] + r[1]) / 2)

        centres = [(r[0] + r[1]) / 2 for r in rows]
        pitches = [b - a for a, b in zip(centres, centres[1:])]
        pitch = statistics.median(pitches) if pitches else 0

        lines = []
        for i, r in enumerate(rows):
            if i and pitch and (centres[i] - centres[i - 1]) > pitch * gap_ratio:
                lines.append("")
            lines.append(r[5])

        (out / f"{p.stem}.paddleocr.txt").write_text(
            "\n".join(lines) + "\n", encoding="utf-8"
        )
        with (out / f"{p.stem}.paddleocr.boxes.tsv").open("w", encoding="utf-8") as fh:
            fh.write("y_top\ty_bot\tx_left\tx_right\tscore\ttext\n")
            for r in rows:
                fh.write(
                    f"{r[0]:.0f}\t{r[1]:.0f}\t{r[2]:.0f}\t{r[3]:.0f}\t{r[4]:.3f}\t{r[5]}\n"
                )
        print(f"{p.name}: {len(rows)} lines, {elapsed:.2f}s")


def emit_structure_mode(images, out):
    from paddleocr import PPStructureV3

    pipeline = PPStructureV3(
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        enable_mkldnn=False,
    )
    for path in images:
        p = pathlib.Path(path)
        t0 = time.perf_counter()
        results = pipeline.predict(str(p))
        elapsed = time.perf_counter() - t0
        chunks = []
        for res in results:
            md = getattr(res, "markdown", None)
            if isinstance(md, dict):
                chunks.append(md.get("markdown_texts", ""))
            elif md is not None:
                chunks.append(str(md))
        (out / f"{p.stem}.ppstructurev3.md").write_text(
            "\n".join(chunks), encoding="utf-8"
        )
        print(f"{p.name}: structure markdown, {elapsed:.2f}s")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=["line", "structure"], default="line")
    ap.add_argument("--gap-ratio", type=float, default=1.6)
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    if args.mode == "line":
        emit_line_mode(args.images, out, args.gap_ratio)
    else:
        emit_structure_mode(args.images, out)


if __name__ == "__main__":
    main()
