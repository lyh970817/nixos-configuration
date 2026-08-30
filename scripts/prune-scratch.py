#!/usr/bin/env python3
"""Guarded one-off removal of finished Claude Code session scratch directories.

Deletions in this configuration never go through `rm`, `rmdir`, `find -delete`,
`xargs rm` or a bare `shutil.rmtree`. Every removal happens here, behind checks
that are re-run against the live filesystem immediately before each unlink.

The targets are hardcoded below. There is deliberately no way to pass a path in
on the command line: an argument that expands to nothing, or to something
unintended, is the failure mode this script exists to make impossible.

Before running this, the container images in the target trees must already be
in the persistent cache -- see home/programs/apptainer.nix for where that is
and why. This script does not preserve anything.

Usage:
    scripts/prune-scratch.py              # dry run (default): plan and sizes
    scripts/prune-scratch.py --delete     # actually remove
"""

from __future__ import annotations

import argparse
import os
import stat
import sys
import time

# --------------------------------------------------------------------------
# What may be removed. Hardcoded, never derived from a variable or an argument.
# --------------------------------------------------------------------------

TARGETS = [
    "/tmp/claude-1000/-home-andongni-Yandex-Disk-Projects-Research-qc-dev-gwas/9d7b66ff-4391-448d-8397-28cf709f8fb8",
    "/tmp/claude-1000/-home-andongni-Yandex-Disk-Projects-Research-pipelines-ilovedata/ae8d65a8-4f02-45d8-ac13-ccf69bc5ade5",
]

# A target must live under one of these. Checked before and after realpath().
ALLOWED_ROOTS = [
    "/tmp/claude-1000",
]

# A target must have at least this many path components, so that a truncated or
# mangled path can never resolve to a directory that matters:
# /tmp (1), /tmp/claude-1000 (2) and /tmp/claude-1000/<project> (3) all fail;
# /tmp/claude-1000/<project>/<session-uuid> (4) is the shallowest legal target.
MIN_DEPTH = 4

# Refuse if the target IS one of these or is an ancestor of one of these --
# removing it would take the listed path with it.
DENY_EQUAL_OR_ANCESTOR = [
    "/",
    "/boot",
    "/etc",
    "/home",
    "/home/andongni",
    "/nix",
    "/run",
    "/tmp",
    "/usr",
    "/var",
]

# Refuse if the target IS one of these or lies inside one of these.
DENY_SUBTREE = [
    "/boot",
    "/etc",
    "/home/andongni/.apptainer",
    "/home/andongni/.nixos-config",
    "/home/andongni/Yandex.Disk",
    "/nix",
    "/run",
    "/usr",
    "/var",
]

# A tree whose newest mtime is fresher than this is treated as possibly live.
DEFAULT_MIN_IDLE_DAYS = 2


class Refused(Exception):
    """A structural guard rejected a path: it is not the shape of thing this
    script is allowed to touch. Never caught -- it aborts the whole run, on the
    assumption that a malformed target means the target list itself is wrong."""


class Skipped(Exception):
    """A liveness guard rejected a path: the path is legal, but something is
    still using it. Caught per target so the rest of the plan is still shown."""


# --------------------------------------------------------------------------
# Guards
# --------------------------------------------------------------------------


def components(path: str) -> list[str]:
    return [c for c in path.split("/") if c]


def is_within(path: str, root: str) -> bool:
    """True if path == root or path is under root. Component-wise, so that
    /tmp/claude-10000 is not treated as being inside /tmp/claude-1000."""
    p, r = components(path), components(root)
    return p[: len(r)] == r


def check_static(path: str, label: str) -> None:
    """Checks that do not touch the filesystem."""
    if not path.startswith("/"):
        raise Refused(f"{label}: not absolute: {path!r}")
    if path != os.path.normpath(path):
        raise Refused(f"{label}: not normalised (.. or // or trailing /): {path!r}")
    if len(components(path)) < MIN_DEPTH:
        raise Refused(f"{label}: only {len(components(path))} components, need >= {MIN_DEPTH}: {path}")
    if not any(is_within(path, root) for root in ALLOWED_ROOTS):
        raise Refused(f"{label}: outside every allowed root {ALLOWED_ROOTS}: {path}")
    for deny in DENY_EQUAL_OR_ANCESTOR:
        if is_within(deny, path):
            raise Refused(f"{label}: is {deny} or an ancestor of it: {path}")
    for deny in DENY_SUBTREE:
        if is_within(path, deny):
            raise Refused(f"{label}: lies inside protected subtree {deny}: {path}")


def check_live(path: str, label: str) -> os.stat_result:
    """Checks against the filesystem as it is right now. Returns the lstat."""
    st = os.lstat(path)          # lstat: never follows a symlink

    if stat.S_ISLNK(st.st_mode):
        raise Refused(f"{label}: is a symlink: {path}")
    if not stat.S_ISDIR(st.st_mode):
        raise Refused(f"{label}: is not a directory: {path}")

    # Resolve, then re-run every static guard on the resolved path. A symlink
    # anywhere in the parent chain could otherwise land us outside the roots.
    real = os.path.realpath(path)
    if real != path:
        raise Refused(f"{label}: resolves elsewhere: {path} -> {real}")
    check_static(real, f"{label} (resolved)")

    # Do not cross a filesystem boundary: the target must sit on the same
    # device as its parent, so a mount point can never be descended into.
    parent_st = os.lstat(os.path.dirname(path))
    if st.st_dev != parent_st.st_dev:
        raise Refused(f"{label}: is a mount point (dev {st.st_dev} != parent {parent_st.st_dev}): {path}")

    return st


def open_files_under(path: str) -> list[str]:
    """Processes with a cwd or an open file inside path -- i.e. a live session."""
    hits = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        candidates = [f"/proc/{pid}/cwd"]
        fddir = f"/proc/{pid}/fd"
        try:
            candidates += [f"{fddir}/{fd}" for fd in os.listdir(fddir)]
        except OSError:
            pass
        for link in candidates:
            try:
                target = os.readlink(link)
            except OSError:
                continue
            if target.startswith("/") and is_within(target, path):
                hits.append(f"pid {pid}: {target}")
                break
    return hits


def tree_stats(path: str, dev: int) -> tuple[int, int, float]:
    """(bytes, entries, newest mtime) for path, without crossing devices."""
    total = entries = 0
    newest = 0.0
    for dirpath, dirnames, filenames in os.walk(path, onerror=lambda e: None):
        try:
            if os.lstat(dirpath).st_dev != dev:
                dirnames[:] = []
                continue
        except OSError:
            continue
        # Never descend through a symlinked directory.
        dirnames[:] = [d for d in dirnames if not os.path.islink(os.path.join(dirpath, d))]
        for name in dirnames + filenames:
            try:
                st = os.lstat(os.path.join(dirpath, name))
            except OSError:
                continue
            entries += 1
            newest = max(newest, st.st_mtime)
            if stat.S_ISREG(st.st_mode):
                total += st.st_blocks * 512
    return total, entries, newest


# --------------------------------------------------------------------------
# Removal
# --------------------------------------------------------------------------


def remove_tree(root: str, dev: int) -> tuple[int, int]:
    """Depth-first removal, re-validating every entry as it is reached.

    Not shutil.rmtree: each unlink is preceded by a fresh lstat, a device
    check and a containment check against root, so a symlink or a bind mount
    appearing mid-run cannot lead the deletion outside the tree.
    """
    files = dirs = 0

    for dirpath, dirnames, filenames in os.walk(root, topdown=False, onerror=lambda e: None):
        if not is_within(dirpath, root):
            raise Refused(f"walk escaped the target: {dirpath} not under {root}")
        try:
            if os.lstat(dirpath).st_dev != dev:
                raise Refused(f"walk crossed a filesystem boundary at {dirpath}")
        except FileNotFoundError:
            continue

        for name in filenames:
            p = os.path.join(dirpath, name)
            try:
                st = os.lstat(p)
            except FileNotFoundError:
                continue
            if stat.S_ISDIR(st.st_mode):
                continue                      # handled by the walk itself
            if st.st_dev != dev and not stat.S_ISLNK(st.st_mode):
                raise Refused(f"entry on another filesystem: {p}")
            os.unlink(p)                      # symlinks are unlinked, not followed
            files += 1

        for name in dirnames:
            p = os.path.join(dirpath, name)
            try:
                st = os.lstat(p)
            except FileNotFoundError:
                continue
            if stat.S_ISLNK(st.st_mode):
                os.unlink(p)                  # a symlink to a directory
                files += 1
                continue
            if st.st_dev != dev:
                raise Refused(f"refusing to remove mount point {p}")
            try:
                os.rmdir(p)                   # rmdir only ever removes an empty dir
                dirs += 1
            except OSError as exc:
                raise Refused(f"could not remove {p}: {exc}") from exc

    os.rmdir(root)
    dirs += 1
    return files, dirs


# --------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--delete", action="store_true", help="actually remove (default is a dry run)")
    ap.add_argument("--min-idle-days", type=float, default=DEFAULT_MIN_IDLE_DAYS,
                    help=f"refuse a tree written to more recently than this (default {DEFAULT_MIN_IDLE_DAYS})")
    args = ap.parse_args()

    now = time.time()
    plan = []
    skipped = []

    print(f"targets: {len(TARGETS)}   mode: {'DELETE' if args.delete else 'dry run'}\n")

    for path in TARGETS:
        label = "target"
        # Structural guards: a failure here aborts everything.
        check_static(path, label)
        st = check_live(path, label)

        size, entries, newest = tree_stats(path, st.st_dev)
        idle_days = (now - newest) / 86400 if newest else float("inf")

        print(f"{path}")
        print(f"    {size/2**30:8.2f} GiB   {entries:>8} entries   idle {idle_days:6.2f} d")

        # Liveness guards: a failure here drops this target only.
        try:
            if idle_days < args.min_idle_days:
                raise Skipped(f"written to {idle_days:.2f} d ago, under --min-idle-days "
                              f"{args.min_idle_days}: this session looks live")
            holders = open_files_under(path)
            if holders:
                for h in holders[:10]:
                    print(f"        held by {h}")
                raise Skipped(f"{len(holders)} running process(es) hold files under it")
        except Skipped as exc:
            print(f"    SKIPPED: {exc}\n")
            skipped.append((path, str(exc)))
            continue

        print("    idle, and no process holds a file under it\n")
        plan.append((path, st.st_dev, size, entries))

    total = sum(p[2] for p in plan)
    print(f"to remove: {len(plan)} of {len(TARGETS)} targets, "
          f"{total/2**30:.2f} GiB across {sum(p[3] for p in plan)} entries")
    if skipped:
        print(f"skipped:   {len(skipped)}")
        for path, why in skipped:
            print(f"    {path}\n        {why}")

    if not args.delete:
        print("\ndry run -- nothing was removed. Re-run with --delete to act.")
        return 0

    for path, dev, _size, _entries in plan:
        # TOCTOU: everything above described the filesystem as it was during
        # planning. Re-establish it from scratch immediately before touching it.
        check_static(path, "target (recheck)")
        st = check_live(path, "target (recheck)")
        if st.st_dev != dev:
            raise Refused(f"device changed under us: {path}")
        holders = open_files_under(path)
        if holders:
            raise Refused(f"a process started using {path}: {holders[0]}")
        _size, _ents, newest = tree_stats(path, st.st_dev)
        if (time.time() - newest) / 86400 < args.min_idle_days:
            raise Refused(f"something wrote into {path} since planning")

        files, dirs = remove_tree(path, st.st_dev)
        print(f"removed {files} files and {dirs} directories: {path}")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Refused as exc:
        print(f"REFUSED: {exc}", file=sys.stderr)
        sys.exit(2)
