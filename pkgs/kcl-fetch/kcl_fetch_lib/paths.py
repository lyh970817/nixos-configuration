"""XDG locations, all dedicated to this tool.

The browser profile in particular is deliberately *not* the user's everyday
Chromium profile: this one accumulates publisher SP session cookies and an
institutional IdP session, and nothing else should be able to ride on them.

Which is why nothing here is left to the ambient umask. `mkdir(mode=0o700)` is
not enough on its own -- the mode is masked by the umask on creation, and it is
ignored outright when the directory already exists. A non-interactive SSH shell
(umask 022) really did leave the state directory 0755 and the ledger 0644 where
an interactive one produced 0700/0600. So every directory and file this tool
owns gets an explicit `chmod` after creation, on every run, which also repairs
whatever an earlier umask left behind. Repair is in place: a directory is never
removed and recreated, because doing that to the profile would destroy a live
session.
"""

from __future__ import annotations

import os
import stat
from pathlib import Path

APP = "kcl-fetch"

#: Owner-only, always. The profile directory is a credential store and the
#: ledger is a record of what was read and when; neither is anyone else's
#: business, including other accounts on the same machine.
DIR_MODE = 0o700
FILE_MODE = 0o600


def _base(var: str, fallback: str) -> Path:
    return Path(os.environ.get(var) or os.path.join(os.path.expanduser("~"), fallback))


def state_dir() -> Path:
    return _base("XDG_STATE_HOME", ".local/state") / APP


def data_dir() -> Path:
    return _base("XDG_DATA_HOME", ".local/share") / APP


def config_dir() -> Path:
    return _base("XDG_CONFIG_HOME", ".config") / APP


def ledger_path() -> Path:
    return state_dir() / "ledger.sqlite3"


def lock_path() -> Path:
    return state_dir() / "fetch.lock"


def routes_path() -> Path:
    return state_dir() / "routes.json"


def profile_dir() -> Path:
    return data_dir() / "profile"


def config_path() -> Path:
    return config_dir() / "config.json"


def libkey_path() -> Path:
    return config_dir() / "libkey"


# -- permissions ------------------------------------------------------------


def _app_roots() -> tuple[Path, ...]:
    """The three directories this tool owns outright."""
    return (state_dir(), data_dir(), config_dir())


def _owned(path: Path) -> list[Path]:
    """`path` plus every ancestor down to the app root it lives under.

    Anything above that root -- `~/.local/state`, `~`, `/` -- belongs to the
    user and is left exactly as it is found. A path outside all three roots
    (a caller passing its own directory, as the tests do) is treated as owned
    on its own, without walking up into someone else's tree.
    """
    chain: list[Path] = []
    for root in _app_roots():
        if path == root or root in path.parents:
            current = path
            while True:
                chain.append(current)
                if current == root:
                    break
                current = current.parent
            return chain
    return [path]


def set_mode(path: Path, mode: int) -> bool:
    """Force `mode` on an existing path. Returns whether anything changed.

    The read-before-write makes the already-correct case a genuine no-op: no
    `chmod` syscall, so nothing's ctime moves on a run that had nothing to fix.
    """
    if stat.S_IMODE(path.stat().st_mode) == mode:
        return False
    os.chmod(path, mode)
    return True


def ensure(path: Path) -> Path:
    """Create `path` if absent, and make it -- and its app-owned parents -- 0700.

    Safe to call on a directory that already exists and already holds data:
    the mode is repaired in place and the contents are untouched.
    """
    path = Path(path)
    path.mkdir(parents=True, exist_ok=True, mode=DIR_MODE)
    for owned in _owned(path):
        set_mode(owned, DIR_MODE)
    return path


def secure_file(path: Path) -> Path:
    """Force 0600 on a file this tool wrote. A missing file is not an error."""
    path = Path(path)
    if path.exists():
        set_mode(path, FILE_MODE)
    return path
