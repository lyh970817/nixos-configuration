#!/usr/bin/env bash
# Run the PaddleOCR venv on NixOS.
#
# PaddleX pins `opencv-contrib-python==4.10.0.84` and checks for it by
# distribution name, so the usual NixOS fix of substituting the -headless wheel
# makes the pipeline refuse to start ("A dependency error occurred during
# pipeline creation"). The pinned GUI wheel must therefore stay installed, and
# its FHS-expected shared libraries supplied from nixpkgs at run time. The -L
# entries nix-shell puts in NIX_LDFLAGS are reused as LD_LIBRARY_PATH.
#
# Usage: run-paddle.sh <args to paddle-ocr.py ...>
set -euo pipefail

here=$(dirname "$(realpath "$0")")
venv=${PADDLE_VENV:-/home/andongni/.config/claude/jobs/eef50db2/tmp/venv-paddle}
export PADDLE_PDX_CACHE_HOME=${PADDLE_PDX_CACHE_HOME:-/home/andongni/.config/claude/jobs/eef50db2/tmp/paddlex-cache}

exec nix-shell -p libGL glib zlib xorg.libxcb xorg.libX11 xorg.libXext \
                  xorg.libSM xorg.libICE \
  --run "export LD_LIBRARY_PATH=\$(printf '%s\n' \$NIX_LDFLAGS | tr ' ' '\n' \
             | sed -n 's/^-L//p' | paste -sd: -); \
         exec $venv/bin/python $here/paddle-ocr.py $*"
