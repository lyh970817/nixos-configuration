"""XDG locations, all dedicated to this tool.

The browser profile in particular is deliberately *not* the user's everyday
Chromium profile: this one accumulates publisher SP session cookies and an
institutional IdP session, and nothing else should be able to ride on them.
"""

from __future__ import annotations

import os
from pathlib import Path

APP = "kcl-fetch"


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


def ensure(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path
