#!/usr/bin/env bash
# Produce the phase-1 evaluation bundle: for each sample page, a readable page
# image plus each shortlisted tool's RAW, unedited output.
#
# Each tool is given the input it performs best on rather than one common
# image, so no tool is handicapped by a choice made for another:
#   - tesseract   178 dpi (the scan's native resolution) with --psm 4.
#                 Upscaling measurably HURTS tesseract here, and --psm 4 is the
#                 only mode that preserves stanza blank lines.
#   - rapidocr    200 dpi. Output is invariant from 178 to 600 dpi, so the
#                 lowest adequate resolution is used to keep it fast.
#   - paddleocr   200 dpi, same reasoning.
#   - ppstructurev3  200 dpi. Included only as the reflow control.
# The distributed pg-NNN.png is rendered at 300 dpi purely so it is comfortable
# to read on screen.
#
# Usage: make-samples.sh <pdf> <outdir> <page> [page ...]
set -euo pipefail

pdf=$(realpath "$1"); shift
out=$(realpath -m "$1"); shift
pages=("$@")

here=$(dirname "$(realpath "$0")")
tmp=/home/andongni/.config/claude/jobs/eef50db2/tmp
rapid_py=$tmp/venv-rapid/bin/python

mkdir -p "$out" "$tmp/samples-178" "$tmp/samples-200"

for p in "${pages[@]}"; do
  n=$(printf '%03d' "$p")
  # Reader copy.
  pdftoppm -r 300 -f "$p" -l "$p" -png -singlefile "$pdf" "$out/pg-$n" 2>/dev/null
  # Per-tool inputs.
  pdftoppm -r 178 -f "$p" -l "$p" -png -singlefile "$pdf" "$tmp/samples-178/pg-$n" 2>/dev/null
  pdftoppm -r 200 -f "$p" -l "$p" -png -singlefile "$pdf" "$tmp/samples-200/pg-$n" 2>/dev/null
done

# --- tesseract baseline -----------------------------------------------------
for p in "${pages[@]}"; do
  n=$(printf '%03d' "$p")
  tesseract "$tmp/samples-178/pg-$n.png" "$out/pg-$n.tesseract" \
    -l chi_sim --psm 4 2>/dev/null
done

# --- RapidOCR line-level ----------------------------------------------------
imgs=()
for p in "${pages[@]}"; do imgs+=("$tmp/samples-200/pg-$(printf '%03d' "$p").png"); done
"$rapid_py" "$here/line-ocr.py" --out "$out" --tag rapidocr "${imgs[@]}" 2>&1 \
  | grep -v 'INFO\|WARNING' || true

# --- PaddleOCR line-level, and PP-StructureV3 as the reflow control ---------
"$here/run-paddle.sh" --mode line --out "$out" "${imgs[@]}" 2>&1 | tail -n +1 \
  | grep -E '^pg-' || true
"$here/run-paddle.sh" --mode structure --out "$out" "${imgs[@]}" 2>&1 \
  | grep -E '^pg-' || true

echo "sample bundle written to $out"
