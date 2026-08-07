#!/usr/bin/env python3
"""Collapse byte-identical icons in a theme tree back into symlinks.

One-shot maintenance tool, kept for the next time an icon theme is vendored.
assets/icons/Matrix-Icons arrived with every symlink dereferenced and with an
@2x copy of each icon, so 8k distinct icons were stored 176k times: 990M for a
theme that is 56M once the sharing is restored. Replacing each duplicate with
a relative symlink to one canonical copy is lossless for icon lookup, since
GTK resolves symlinks, and leaves the set of icon paths exactly as it was.

Symlinks are relative so the tree stays self-contained and relocatable, which
is what lets the Nix build copy it with `cp -a` and keep the sharing.

Usage: scripts/icon-theme-relink.py assets/icons/<Theme>
"""

from __future__ import annotations

import hashlib
import os
import sys


def digest(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def relink(root: str) -> tuple[int, int]:
    # Sorted walk so the canonical copy for a given digest is chosen
    # deterministically; the build must be reproducible.
    canonical: dict[str, str] = {}
    linked = 0
    total = 0

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            total += 1
            key = digest(path)
            keeper = canonical.get(key)
            if keeper is None:
                canonical[key] = path
                continue
            os.remove(path)
            os.symlink(os.path.relpath(keeper, dirpath), path)
            linked += 1

    return total, linked


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: matrix-icons-relink.py <theme-dir>", file=sys.stderr)
        return 2
    total, linked = relink(sys.argv[1])
    print(f"relinked {linked} of {total} files ({total - linked} unique)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
