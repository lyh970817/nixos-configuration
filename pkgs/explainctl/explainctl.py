#!/usr/bin/env python3
"""Entry point for explainctl; the script directory is on sys.path, so the
adjacent explainctl_lib package resolves both from the Nix install layout
and from a source checkout."""

import sys

from explainctl_lib.cli import main

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
