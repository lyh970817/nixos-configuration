#!/usr/bin/env bash
# Extract the page images at their NATIVE resolution with both decoders, so a
# poppler-vs-mupdf comparison isolates the JBIG2 decoder itself rather than
# each renderer's rescaling filter.
#
# Usage: extract-native.sh <pdf> <outdir> <page> [page ...]
set -euo pipefail

pdf=$(realpath "$1"); shift
out=$(realpath -m "$1"); shift

mkdir -p "$out/poppler" "$out/mupdf"

for p in "$@"; do
  n=$(printf '%03d' "$p")
  # poppler: decode the embedded image stream directly.
  pdfimages -f "$p" -l "$p" -png "$pdf" "$out/poppler/pg-$n" 2>/dev/null || true

  # mupdf: same, but `mutool extract` takes the PDF *object* number and always
  # writes into the current directory, so run it in a scratch dir and rename.
  obj=$(pdfimages -list -f "$p" -l "$p" "$pdf" 2>/dev/null | awk 'NR>2 {print $11; exit}')
  scratch="$out/mupdf/scratch"
  rm -rf "$scratch"; mkdir -p "$scratch"
  ( cd "$scratch" && mutool extract "$pdf" "$obj" >/dev/null 2>&1 ) || true
  for f in "$scratch"/*; do
    [ -e "$f" ] || continue
    mv "$f" "$out/mupdf/pg-$n.${f##*.}"
  done
  rm -rf "$scratch"
done
