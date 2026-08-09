#!/usr/bin/env bash
# Sweep tesseract render resolution and page-segmentation mode on one page, to
# check whether the baseline's poor accuracy is a preprocessing problem or a
# model problem. Must be run inside a nix-shell providing tesseract + poppler.
#
# Usage: tess-sweep.sh <pdf> <page> <workdir>
set -euo pipefail

pdf=$1
page=$2
work=$3
mkdir -p "$work"

for dpi in 178 300 400 600; do
  img="$work/sweep-$dpi"
  [ -f "$img.png" ] || pdftoppm -r "$dpi" -f "$page" -l "$page" -png -singlefile "$pdf" "$img" 2>/dev/null
  for psm in 4 6; do
    out="$work/sweep-r$dpi-psm$psm"
    s=$(date +%s.%N)
    tesseract "$img.png" "$out" -l chi_sim --psm "$psm" 2>/dev/null
    e=$(date +%s.%N)
    printf '===== dpi=%s psm=%s  %.2fs\n' "$dpi" "$psm" "$(echo "$e - $s" | bc)"
    cat "$out.txt"
  done
done
