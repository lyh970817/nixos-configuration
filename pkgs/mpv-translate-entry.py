#!/usr/bin/env python3
"""Start the unchanged upstream CLI with the CPU runtimes initialized in order."""

import pathlib
import sys

# Loading Torch after CTranslate2 inference crashes in OpenBLAS GEMM on both
# hosts. Initialize Torch first; changing OMP/OPENBLAS thread counts was insufficient.
import torch

from mpv_translate.cli import cli, direct


commands = {"mpv-translate": cli, "mpv-translate-direct": direct}
commands[pathlib.Path(sys.argv[0]).name]()
