#!/usr/bin/env python3
"""Trash-then-purge the segments of a cancelled screen recording.

`screen-record cancel` throws a recording away on purpose, and these files run
to hundreds of megabytes or gigabytes each, so they must not pile up in the
desktop wastebasket the way `gio trash` leaves them -- that is why the cancel
path calls this instead. They still must not be unlinked outright: the project
rule is trash-then-purge, never unlink as the first action, so a mistake stays
reversible until the very last step. Every segment is therefore renamed into a
timestamped batch directory beside it, recorded in a JSON manifest, verified in
its new place, and only then unlinked. Any refusal anywhere in that sequence
stops before the purge and leaves the whole batch sitting on disk under
<recordings>/.discard-<stamp>/, manifest included, for a human to look at.

The rename is deliberately a same-directory rename: it is atomic, it costs
nothing for a gigabyte file, and it cannot half-copy. It is also why the batch
lives inside the recordings directory rather than somewhere tidier -- anywhere
else risks crossing a filesystem and turning the move into a copy.

The guards mirror ~/Yandex.Disk/Projects/safe_delete.py, which cannot be used
directly here: its ALLOWED_ROOTS do not cover ~/Videos, and widening them to
suit one caller would permanently weaken a global guard for a one-off.

Exit status: 0 done (or nothing to do), 2 refused or failed -- and on 2 nothing
has been purged.
"""

import argparse
import fnmatch
import json
import os
import stat
import sys
from datetime import datetime

# The recordings root itself must not be one of these, whatever it resolves to.
PROTECTED_ROOTS = frozenset(
    (
        "/",
        "/boot",
        "/dev",
        "/etc",
        "/home",
        "/nix",
        "/proc",
        "/root",
        "/run",
        "/srv",
        "/sys",
        "/tmp",
        "/usr",
        "/var",
    )
)

# screen-record.sh builds rec_dir as "<videos>/Recordings" and names every file
# it writes screenrecord_<stamp>.mp4 or screenrecord_<stamp>.partNNN.mp4.
ROOT_BASENAME = "Recordings"
SEGMENT_GLOB = "screenrecord_*.mp4"
BATCH_PREFIX = ".discard-"
MANIFEST_NAME = "manifest.json"
# Below this many path components a root is too close to the filesystem root to
# be a plausible recordings directory, so "/", "/home" and "/home/user" cannot
# pass however they were spelled.
MIN_ROOT_DEPTH = 3


class Refused(Exception):
    """A guard said no. Nothing has been purged."""


def log(message):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}", flush=True)


def resolve_root(raw):
    """The one allowlisted root. Everything else is checked against this."""
    if not os.path.isabs(raw):
        raise Refused(f"recordings root is not absolute: {raw}")
    root = os.path.realpath(raw)
    if root in PROTECTED_ROOTS:
        raise Refused(f"recordings root is a protected directory: {root}")
    if len([p for p in root.split("/") if p]) < MIN_ROOT_DEPTH:
        raise Refused(f"recordings root is too shallow: {root}")
    if os.path.basename(root) != ROOT_BASENAME:
        raise Refused(f"recordings root is not a {ROOT_BASENAME} directory: {root}")
    if not os.path.isdir(root):
        raise Refused(f"recordings root is not a directory: {root}")
    return root


def inspect(path, root, root_dev):
    """Validate one candidate segment.

    Returns its manifest entry, or None when there is simply nothing there --
    a segment the recorder never wrote is not an error. Raises Refused for
    anything that does not look exactly like a segment this script wrote.
    """
    if not os.path.isabs(path):
        raise Refused(f"segment path is not absolute: {path}")
    if ".." in path.split("/"):
        raise Refused(f"segment path contains a .. component: {path}")

    base = os.path.basename(path)
    if not base:
        raise Refused(f"segment path has no basename: {path}")
    if not fnmatch.fnmatch(base, SEGMENT_GLOB):
        raise Refused(f"segment name is not a recording segment: {base}")
    # Containment before resolving: a direct child of the recordings root.
    if os.path.dirname(path) != root and os.path.realpath(os.path.dirname(path)) != root:
        raise Refused(f"segment is not in the recordings directory: {path}")

    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(st.st_mode):
        raise Refused(f"segment is a symlink: {path}")
    if not stat.S_ISREG(st.st_mode):
        raise Refused(f"segment is not a regular file: {path}")
    # Containment again, after resolving: a symlinked parent directory would
    # otherwise let a path that passed the checks above land outside the root.
    real = os.path.realpath(path)
    if real != os.path.join(root, base):
        raise Refused(f"segment resolves outside the recordings directory: {path}")
    if st.st_dev != root_dev:
        raise Refused(f"segment is on another filesystem: {path}")

    return {
        "original": path,
        "name": base,
        "bytes": st.st_size,
        "dev": st.st_dev,
        "ino": st.st_ino,
    }


def write_manifest(batch, payload):
    path = os.path.join(batch, MANIFEST_NAME)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return path


def move_into_batch(entries, root):
    """Rename every entry into a fresh batch directory and verify each move."""
    stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    batch = os.path.join(root, f"{BATCH_PREFIX}{stamp}-{os.getpid()}")
    # Plain mkdir, not makedirs: a collision must be an error, never a reuse of
    # a directory this run did not create.
    os.mkdir(batch, 0o700)

    payload = {"created": stamp, "root": root, "purged": False, "entries": entries}
    write_manifest(batch, payload)

    for entry in entries:
        source = entry["original"]
        target = os.path.join(batch, entry["name"])
        if os.path.lexists(target):
            raise Refused(f"batch already holds {entry['name']}")
        os.rename(source, target)

        # Verify the move landed before anything is allowed to be purged.
        moved = os.lstat(target)
        if stat.S_ISLNK(moved.st_mode) or not stat.S_ISREG(moved.st_mode):
            raise Refused(f"moved segment is not a regular file: {target}")
        if moved.st_ino != entry["ino"] or moved.st_dev != entry["dev"]:
            raise Refused(f"moved segment is not the file that was checked: {target}")
        if moved.st_size != entry["bytes"]:
            raise Refused(f"moved segment changed size: {target}")
        if os.path.lexists(source):
            raise Refused(f"segment still present after the move: {source}")
        entry["moved"] = True
        log(f"trashed {source} -> {target} ({entry['bytes']} bytes)")

    write_manifest(batch, payload)
    return batch, payload


def purge_batch(batch, payload, root, root_dev):
    """Unlink a batch that has been moved and verified. The last step."""
    base = os.path.basename(batch)
    if not base.startswith(BATCH_PREFIX):
        raise Refused(f"not a discard batch: {batch}")
    if os.path.realpath(batch) != os.path.join(root, base):
        raise Refused(f"discard batch is not in the recordings directory: {batch}")
    batch_st = os.lstat(batch)
    if stat.S_ISLNK(batch_st.st_mode) or not stat.S_ISDIR(batch_st.st_mode):
        raise Refused(f"discard batch is not a directory: {batch}")
    if batch_st.st_dev != root_dev:
        raise Refused(f"discard batch is on another filesystem: {batch}")

    expected = {entry["name"] for entry in payload["entries"]}
    present = set(os.listdir(batch))
    unexpected = present - expected - {MANIFEST_NAME}
    if unexpected:
        raise Refused(f"discard batch holds unexpected files: {sorted(unexpected)}")
    missing = expected - present
    if missing:
        raise Refused(f"discard batch is missing entries: {sorted(missing)}")

    total = 0
    for entry in payload["entries"]:
        target = os.path.join(batch, entry["name"])
        # TOCTOU: re-verify the shape immediately before the unlink, not only
        # when the batch was assembled.
        final = os.lstat(target)
        if stat.S_ISLNK(final.st_mode) or not stat.S_ISREG(final.st_mode):
            raise Refused(f"refusing to purge a non-regular file: {target}")
        if final.st_ino != entry["ino"] or final.st_dev != entry["dev"]:
            raise Refused(f"refusing to purge an unexpected file: {target}")
        if not fnmatch.fnmatch(entry["name"], SEGMENT_GLOB):
            raise Refused(f"refusing to purge an unexpected name: {entry['name']}")
        os.unlink(target)
        total += entry["bytes"]
        log(f"purged {entry['original']} ({entry['bytes']} bytes, {total} total)")

    os.unlink(os.path.join(batch, MANIFEST_NAME))
    os.rmdir(batch)
    log(f"purged {len(payload['entries'])} segment(s), {total} bytes total")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, help="the recordings directory")
    parser.add_argument(
        "--purge",
        action="store_true",
        help="actually act; without it this only prints the plan",
    )
    parser.add_argument("paths", nargs="*", help="absolute segment paths")
    args = parser.parse_args(argv)

    try:
        root = resolve_root(args.root)
        root_dev = os.lstat(root).st_dev

        entries = []
        seen = set()
        for path in args.paths:
            if path in seen:
                continue
            seen.add(path)
            entry = inspect(path, root, root_dev)
            if entry is None:
                continue
            if entry["name"] in {e["name"] for e in entries}:
                raise Refused(f"duplicate segment name: {entry['name']}")
            entries.append(entry)

        if not entries:
            log("nothing to discard")
            return 0

        if not args.purge:
            for entry in entries:
                log(f"would discard {entry['original']} ({entry['bytes']} bytes)")
            return 0

        batch, payload = move_into_batch(entries, root)
        purge_batch(batch, payload, root, root_dev)
    except Refused as exc:
        print(f"discard-segments: refused: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"discard-segments: failed: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
