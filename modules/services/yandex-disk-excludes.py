"""Generate the Yandex.Disk exclude-dirs list from churn rules and markers.

Scans the sync directory and writes the union of the static entries, the
directories matched by the churn rules (NAMED, rule_for, content_rule), and
every directory
holding a .yandex-nosync marker into config.cfg's exclude-dirs= line.

Exit status: 0 the list is unchanged, 1 it changed (written, or would be
written under --dry-run/--check), 2 error.
"""

import argparse
import difflib
import os
import sys
import tempfile
import time

MARKER = ".yandex-nosync"
KEY = "exclude-dirs="
CACHEDIR_SIGNATURE = b"Signature: 8a477f597d28d172789f06886806bc55"

# Tool caches and checkouts excluded by directory name alone: each name is
# owned by the tool that creates it and never holds hand-made data.
NAMED = {
    ".nextflow": "Nextflow cache",
    ".worktrees": "git worktrees",
    "node_modules": "npm packages",
    ".venv": "Python virtualenv",
    "__pycache__": "Python bytecode",
    ".direnv": "direnv cache",
    ".pytest_cache": "pytest cache",
    ".mypy_cache": "mypy cache",
    ".ruff_cache": "ruff cache",
    ".gradle": "Gradle cache",
}
GRADLE_FILES = ("build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts")


def rule_for(name, parent_rel, sibling_dirs, sibling_files):
    """Return the reason a child directory is churn, or None."""
    if name in NAMED:
        return NAMED[name]
    if name == ".nf-test" or name.startswith(".nf-test-"):
        return "nf-test workspace"
    # .claude/worktrees, .sandcastle/worktrees: agent tools keep worktrees
    # under their own dot directory.
    if name == "worktrees" and os.path.basename(parent_rel).startswith("."):
        return "agent worktrees"
    if name == "target" and "Cargo.toml" in sibling_files:
        return "Cargo build output"
    if name == "build" and any(f in sibling_files for f in GRADLE_FILES):
        return "Gradle build output"
    if name == "work":
        if ".nextflow" in sibling_dirs or any(f.startswith(".nextflow.log") for f in sibling_files):
            return "Nextflow work dir"
    return None


def content_rule(path, files):
    """Return the reason a directory is excluded because of what it holds."""
    if MARKER in files:
        return MARKER + " marker"
    if "pyvenv.cfg" in files:
        return "Python virtualenv"
    # https://bford.info/cachedir/: the tag only counts with its signature.
    if "CACHEDIR.TAG" in files:
        try:
            with open(os.path.join(path, "CACHEDIR.TAG"), "rb") as f:
                if f.read(len(CACHEDIR_SIGNATURE)) == CACHEDIR_SIGNATURE:
                    return "CACHEDIR.TAG cache"
        except OSError:
            pass
    return None


def representable(rel):
    """The list is comma-separated inside a quoted config value."""
    try:
        rel.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return not any(c in ',"\\' or ord(c) < 0x20 for c in rel)


def shown(rel):
    return rel.encode("utf-8", "surrogateescape").decode("utf-8", "backslashreplace")


def warn(msg):
    print("yandex-disk-excludes: " + msg, file=sys.stderr)


def scan(root, static):
    """Return ({rel: reason}, directories scanned)."""
    root_dev = os.lstat(root).st_dev
    found = {}
    scanned = 0
    stack = [""]
    while stack:
        rel = stack.pop()
        path = os.path.join(root, rel)
        try:
            with os.scandir(path) as it:
                entries = list(it)
        except OSError as e:
            warn(f"cannot list {shown(rel) or '.'}: {e.strerror}")
            continue
        scanned += 1
        dirs, files = {}, set()
        for e in entries:
            try:
                is_dir = e.is_dir(follow_symlinks=False)
            except OSError:
                is_dir = False
            if is_dir:
                dirs[e.name] = e
            else:
                files.add(e.name)
        reason = content_rule(path, files)
        if reason and rel:
            found[rel] = reason
            continue
        if reason:
            warn(f"ignoring {reason} at the top of the sync dir")
        for name, e in dirs.items():
            child = os.path.join(rel, name) if rel else name
            if name == ".git" or (not rel and name == ".sync") or child in static:
                continue
            try:
                if e.stat(follow_symlinks=False).st_dev != root_dev:
                    continue
            except OSError:
                continue
            reason = rule_for(name, rel, dirs, files)
            if reason:
                found[child] = reason
            else:
                stack.append(child)
    return found, scanned


def drop_nested(entries):
    kept = []
    for entry in sorted(entries):
        if not any(entry.startswith(k + "/") for k in kept):
            kept.append(entry)
    return kept


def covered(entry, current):
    return any(entry == c or entry.startswith(c + "/") for c in current)


def read_config(path):
    """Return (lines, first exclude-dirs line, its entries); None when absent."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines(keepends=True)
    except FileNotFoundError:
        return [], None, None
    for line in lines:
        if line.startswith(KEY):
            value = line[len(KEY):].strip()
            if len(value) >= 2 and value[0] == value[-1] == '"':
                value = value[1:-1]
            return lines, line, [v for v in value.split(",") if v]
    return lines, None, None


def render(entries):
    return KEY + '"' + ",".join(entries) + '"\n'


def write_config(path, lines, entries):
    target = os.path.realpath(path)
    new_line, out, placed = render(entries), [], False
    for line in lines:
        if line.startswith(KEY):
            if not placed:
                out.append(new_line)
                placed = True
            continue
        out.append(line)
    if not placed:
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        out.append(new_line)
    try:
        st = os.stat(target)
    except FileNotFoundError:
        st = None
    directory = os.path.dirname(target)
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".config.cfg.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("".join(out))
            f.flush()
            if st is None:
                os.fchmod(f.fileno(), 0o600)
            else:
                os.fchmod(f.fileno(), st.st_mode & 0o7777)
                if (st.st_uid, st.st_gid) != (os.getuid(), os.getgid()):
                    os.fchown(f.fileno(), st.st_uid, st.st_gid)
            os.fsync(f.fileno())
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise
    dfd = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)


def normalise_static(raw):
    entry = raw.strip("/")
    parts = entry.split("/")
    if not entry or any(p in ("", ".", "..") for p in parts) or not representable(entry):
        raise ValueError(f"invalid --static entry {raw!r}")
    return entry


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--sync-dir", required=True, help="the Yandex.Disk directory to scan")
    p.add_argument("--config", required=True, help="config.cfg whose exclude-dirs= line is managed")
    p.add_argument("--static", action="append", default=[], metavar="PATH", help="always exclude PATH (relative to the sync dir); repeatable")
    mode = p.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="print the list and its diff against config.cfg; write nothing")
    mode.add_argument("--check", action="store_true", help="write nothing; exit 1 if the list would change")
    p.add_argument("--only-if-added", action="store_true", help="count as a change only a path the current list does not already cover; vanished entries alone change nothing")
    args = p.parse_args()

    try:
        static = {normalise_static(s) for s in args.static}
    except ValueError as e:
        p.error(str(e))
    root = os.path.abspath(args.sync_dir)
    started = time.monotonic()
    found, scanned = scan(root, static)
    elapsed = time.monotonic() - started

    generated = {}
    for rel, reason in found.items():
        if representable(rel):
            generated[rel] = reason
        else:
            warn(f"cannot exclude {shown(rel)!r} ({reason}): a comma, quote, backslash or control character cannot appear in exclude-dirs")
    reasons = {s: "static" for s in static}
    reasons.update(generated)
    new = drop_nested(reasons)

    lines, current_line, current = read_config(args.config)
    if args.only_if_added:
        changed = any(not covered(e, current or []) for e in new)
    else:
        changed = current_line != render(new)

    summary = f"scanned {scanned} directories in {elapsed:.1f}s: {len(new)} entries ({len(static)} static)"
    if args.dry_run:
        for entry in new:
            print(f"{entry}\t{reasons[entry]}")
        diff = list(difflib.unified_diff([c + "\n" for c in sorted(current or [])], [e + "\n" for e in new], "current exclude-dirs (sorted)", "generated exclude-dirs", n=0))
        print("".join(diff) if diff else "(no change)", end="" if diff else "\n")
        warn(summary + ("; would change" if changed else "; unchanged"))
    elif args.check:
        warn(summary + ("; would change" if changed else "; unchanged"))
    elif changed:
        write_config(args.config, lines, new)
        old = set(current or [])
        added = [e for e in new if e not in old]
        removed = sorted(old - set(new))
        warn(summary + f"; wrote {args.config}: +{len(added)} -{len(removed)}")
        for e in added:
            warn(f"  + {e} ({reasons[e]})")
        for e in removed:
            warn(f"  - {e}")
    else:
        warn(summary + "; unchanged")
    return 1 if changed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # exit 1 means "changed"; any failure must be 2
        warn(f"failed: {e!r}")
        sys.exit(2)
