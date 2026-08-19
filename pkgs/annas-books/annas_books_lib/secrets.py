"""Membership key loading and redaction.

The key travels in a query string, so it must never reach argv (visible in
`ps`), shell history, or a log line. It is read from the environment or from a
0600 file outside the repository, and everything printed goes through
``redact()`` first.
"""

from __future__ import annotations

import os
import re
import stat
import urllib.parse
from pathlib import Path

ENV_VAR = "ANNAS_SECRET_KEY"

#: Any ``key=`` query parameter, whatever its value. Catches keys this process
#: never loaded (an URL echoed back by the server, a copy/pasted command).
_KEY_PARAM_RE = re.compile(r"(?i)\b(key=)[^&\s\"'<>]+")

REDACTED = "[REDACTED]"


class MissingKeyError(RuntimeError):
    """Raised when no usable membership key is available."""


def default_key_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(
        os.path.expanduser("~"), ".config"
    )
    return Path(base) / "annas-books" / "secret-key"


def load_key(*, env: dict | None = None, key_file: Path | None = None) -> str:
    """Return the membership key from ``$ANNAS_SECRET_KEY`` or the key file.

    The file must not be group- or world-readable; a permissive mode is an
    error rather than a warning, because the alternative is leaking a paid
    credential silently.
    """
    env = os.environ if env is None else env
    from_env = (env.get(ENV_VAR) or "").strip()
    if from_env:
        return from_env

    path = default_key_file() if key_file is None else key_file
    if not path.exists():
        raise MissingKeyError(
            f"no membership key: set ${ENV_VAR} or write it to {path} (chmod 600)"
        )
    mode = path.stat().st_mode
    if mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise MissingKeyError(f"{path} is group/world accessible; run: chmod 600 {path}")
    key = path.read_text(encoding="utf-8").strip()
    if not key:
        raise MissingKeyError(f"{path} is empty")
    return key


def redact(text: str, key: str | None = None) -> str:
    """Mask the key -- literal, percent-encoded, and any ``key=`` parameter."""
    if not isinstance(text, str):
        text = str(text)
    if key:
        for form in (key, urllib.parse.quote(key, safe=""), urllib.parse.quote(key)):
            if form:
                text = text.replace(form, REDACTED)
    return _KEY_PARAM_RE.sub(r"\1" + REDACTED, text)
