#!/usr/bin/env bash
# Sweep the pdftoppm render resolution feeding the line-level OCR, to test
# whether upscaling past the scan's native 178 dpi buys any accuracy.
# Rendering at a higher -r is preferred over upscaling the extracted 1-bit
# image, because poppler rasterises the JBIG2 bitmap with its own filter.
#
# Usage: dpi-sweep.sh <pdf> <page> <workdir> <venv-python> <line-ocr.py>
set -euo pipefail

pdf=$1; page=$2; work=$3; py=$4; script=$5
mkdir -p "$work"

for dpi in 178 200 300 400 600; do
  img="$work/dpi-$dpi"
  [ -f "$img.png" ] || pdftoppm -r "$dpi" -f "$page" -l "$page" -png -singlefile "$pdf" "$img" 2>/dev/null
  echo "===== render dpi=$dpi"
  "$py" "$script" --out "$work/out-$dpi" --tag "r$dpi" "$img.png" 2>&1 | grep -v INFO || true
  cat "$work/out-$dpi/dpi-$dpi.r$dpi.txt"
done
