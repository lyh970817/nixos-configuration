"""Private session persistence and redacted audit storage."""

from __future__ import annotations

import json
import os
import stat
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, NotRequired, TypedDict


AUDIT_TTL_DAYS = 90
AUDIT_MAX_BYTES = 1024 * 1024


class ScreenError(RuntimeError):
    pass


class OwnedProcess(TypedDict):
    pid: int
    start_time: str
    keep_open: bool
    window: NotRequired[dict[str, Any]]


class SessionData(TypedDict):
    session: str
    started_at: str
    mode: str
    captures: int
    processes: list[OwnedProcess]
    previews: NotRequired[list[dict[str, Any]]]
    restore_mode: NotRequired[str]


def now() -> datetime:
    return datetime.now(timezone.utc)


def runtime_root() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR")
    if not base:
        base = f"/run/user/{os.getuid()}"
    return Path(base) / "codex-screen"


def state_root() -> Path:
    base = os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))
    return Path(base) / "codex-screen"


def private_dir(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.chmod(0o700)


def atomic_json(path: Path, value: Any) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


def read_json(path: Path) -> SessionData:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as error:
        raise ScreenError(f"Invalid or missing session: {path.parent.name}") from error


def audit(
    event: str,
    *,
    session: str,
    target: str | None = None,
    monitor: str | None = None,
    outcome: str = "ok",
) -> None:
    root = state_root()
    private_dir(root)
    path = root / "audit.jsonl"
    rotate_audit(path)
    entry = {
        "time": now().isoformat(),
        "session": session,
        "event": event,
        "outcome": outcome,
    }
    if target is not None:
        entry["target"] = target
    if monitor is not None:
        entry["monitor"] = monitor
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, separators=(",", ":")) + "\n")
    path.chmod(0o600)


def rotate_audit(path: Path) -> None:
    if not path.exists():
        return
    cutoff = now() - timedelta(days=AUDIT_TTL_DAYS)
    retained: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            entry = json.loads(line)
            timestamp = datetime.fromisoformat(entry["time"])
        except (json.JSONDecodeError, KeyError, ValueError):
            continue
        if timestamp >= cutoff:
            retained.append(json.dumps(entry, separators=(",", ":")))
    encoded = "\n".join(retained)
    if encoded:
        encoded += "\n"
    while len(encoded.encode()) > AUDIT_MAX_BYTES and retained:
        retained.pop(0)
        encoded = "\n".join(retained)
        if encoded:
            encoded += "\n"
    path.write_text(encoded, encoding="utf-8")
    path.chmod(0o600)


def session_dir(session: str) -> Path:
    if not session or any(
        character not in "abcdefghijklmnopqrstuvwxyz0123456789" for character in session
    ):
        raise ScreenError("Invalid session identifier")
    path = runtime_root() / session
    if not path.is_dir() or path.is_symlink():
        raise ScreenError(f"Invalid or missing session: {session}")
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        raise ScreenError("Session directory is not private")
    return path
