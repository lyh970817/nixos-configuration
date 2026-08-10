#!/usr/bin/env bash
# Render selected PDF pages with poppler (pdftoppm) and mupdf (mutool draw)
# at a given resolution, into two parallel directories, for fidelity comparison.
#
# Usage: render-pages.sh <pdf> <outdir> <dpi> <page> [page ...]
set -euo pipefail

pdf=$1; shift
out=$1; shift
dpi=$1; shift

mkdir -p "$out/poppler" "$out/mupdf"

for p in "$@"; do
  n=$(printf '%03d' "$p")
  pdftoppm -r "$dpi" -f "$p" -l "$p" -png -singlefile "$pdf" "$out/poppler/pg-$n" \
    2> "$out/poppler/pg-$n.stderr" || true
  mutool draw -r "$dpi" -o "$out/mupdf/pg-$n.png" "$pdf" "$p" \
    2> "$out/mupdf/pg-$n.stderr" || true
done
