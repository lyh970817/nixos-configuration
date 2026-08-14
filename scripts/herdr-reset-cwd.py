#!/usr/bin/env python3
"""Reset Herdr's saved pane directories to $HOME after a reboot.

Herdr 0.8.0 restores every pane into the directory it was last in and exposes
no configuration for it: `restore()` in src/persist/restore.rs threads no cwd
policy at all, and `[terminal] new_cwd` is consulted only by the *creation*
paths. The restore source is the on-disk snapshot, so the snapshot is the only
place to intervene.

Rewriting the `cwd` and `identity_cwd` strings -- and nothing else -- keeps the
workspace/tab/pane layout, custom tab names, zoom and focus state, and the
`agent_session` refs that let Herdr resume agent conversations. The rewrite is
key-name driven rather than schema-driven so a future snapshot version that
moves those fields around still gets covered; no other key in the v3 schema is
named `cwd`.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import sys
import tempfile
import time
from pathlib import Path

# The snapshot fields that name a directory Herdr will restore into.
CWD_KEYS = frozenset({"cwd", "identity_cwd"})

SESSION_FILE = "session.json"
API_SOCKET = "herdr.sock"


def config_dir() -> Path:
    """Mirror herdr's own config_dir() (src/config/io.rs)."""
    xdg = os.environ.get("XDG_CONFIG_HOME")
    base = Path(xdg) if xdg else Path.home() / ".config"
    return base / "herdr"


def home_dir() -> Path:
    return Path(os.environ.get("HOME") or Path.home())


def session_dirs(root: Path) -> list[Path]:
    """The default session directory, then every named session under it.

    Named sessions (`herdr --session remote`) restore panes exactly the same
    way, so they get the same treatment.
    """
    dirs = [root]
    sessions = root / "sessions"
    try:
        entries = sorted(sessions.iterdir())
    except OSError:
        return dirs
    dirs.extend(entry for entry in entries if entry.is_dir())
    return dirs


def server_is_live(sock_path: Path) -> bool:
    """Probe the API socket rather than trusting that the file exists.

    Herdr leaves the socket file behind when it dies, so presence alone means
    nothing; only a successful connect() proves a server is serving. Any
    unexpected error is reported as live, because skipping a rewrite is always
    safer than racing a running server for the snapshot file.
    """
    # No socket file at all is unambiguous, and answering it here keeps
    # connect() from having to distinguish "absent" from errors that are about
    # the path rather than the server (AF_UNIX addresses cap out around 108
    # bytes, well short of a filesystem path).
    if not sock_path.exists():
        return False
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    probe.settimeout(2.0)
    try:
        probe.connect(str(sock_path))
    except (FileNotFoundError, ConnectionRefusedError, NotADirectoryError):
        return False
    except OSError:
        return True
    finally:
        probe.close()
    return True


def boot_time() -> float:
    """Wall-clock time at which this boot started."""
    return time.time() - time.clock_gettime(time.CLOCK_BOOTTIME)


def rewrite(node: object, home: str) -> int:
    """Point every cwd-ish string at `home`. Returns the number of changes."""
    changed = 0
    if isinstance(node, dict):
        for key, value in node.items():
            if key in CWD_KEYS and isinstance(value, str):
                if value != home:
                    node[key] = home
                    changed += 1
            else:
                changed += rewrite(value, home)
    elif isinstance(node, list):
        for value in node:
            changed += rewrite(value, home)
    return changed


def write_atomically(path: Path, text: str) -> None:
    """Replace `path` in one step, so a crash can never truncate the snapshot."""
    try:
        mode = path.stat().st_mode & 0o7777
    except OSError:
        mode = 0o600
    handle = tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=".herdr-reset-cwd.",
        suffix=".json",
        delete=False,
    )
    tmp = Path(handle.name)
    try:
        with handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise
    directory = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def reset_session(directory: Path, home: str, force: bool = False) -> str:
    """Reset one session directory. Returns a one-line report for the journal."""
    path = directory / SESSION_FILE
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return f"{path}: no snapshot, nothing to do"
    except OSError as err:
        return f"{path}: unreadable ({err}), left untouched"

    if server_is_live(directory / API_SOCKET):
        return f"{path}: server is live, left untouched"

    if not force:
        try:
            mtime = path.stat().st_mtime
        except OSError as err:
            return f"{path}: unstatable ({err}), left untouched"
        if mtime >= boot_time():
            return f"{path}: written during this boot, left untouched"

    try:
        snapshot = json.loads(raw)
    except (json.JSONDecodeError, UnicodeDecodeError) as err:
        return f"{path}: unparseable ({err}), left untouched"
    if not isinstance(snapshot, dict):
        return f"{path}: not a snapshot object, left untouched"

    changed = rewrite(snapshot, home)
    if not changed:
        return f"{path}: already at {home}"

    # herdr writes the snapshot with serde_json::to_string_pretty, which is a
    # two-space indent and no trailing newline; match it so a rewritten file is
    # indistinguishable from one herdr saved itself.
    write_atomically(path, json.dumps(snapshot, indent=2, ensure_ascii=False))
    return f"{path}: reset {changed} director{'y' if changed == 1 else 'ies'} to {home}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="rewrite even a snapshot already written during this boot "
        "(the live-server guard still applies)",
    )
    args = parser.parse_args(argv)

    home = str(home_dir())
    for directory in session_dirs(config_dir()):
        print(reset_session(directory, home, force=args.force), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
