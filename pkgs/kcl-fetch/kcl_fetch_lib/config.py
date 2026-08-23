"""User configuration -- a one-way valve onto `limits.DEFAULTS`.

There is exactly one knob shape here: `{"limits": {...}}`, and every value in
it must make the tool stricter. A config that would raise a cap or shorten a
wait is rejected outright, so the shipped defaults are a ceiling that no file
on disk and no environment variable can lift.

Concurrency is absent from this file on purpose. It is 1, it is enforced by an
exclusive lock in `gate`, and there is nothing to configure.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from . import paths
from .limits import DEFAULTS, Limits, LimitsConfigError


@dataclass(frozen=True)
class Config:
    limits: Limits = DEFAULTS
    chromium: str | None = None


def load(path: Path | None = None) -> Config:
    path = paths.config_path() if path is None else Path(path)
    if not path.exists():
        return Config()
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as exc:
        raise LimitsConfigError(f"{path}: not valid JSON ({exc})") from exc
    if not isinstance(raw, dict):
        raise LimitsConfigError(f"{path}: expected a JSON object")

    unknown = set(raw) - {"limits", "chromium"}
    if unknown:
        raise LimitsConfigError(f"{path}: unknown keys {sorted(unknown)}")

    try:
        limits = DEFAULTS.tighten(raw.get("limits"))
    except LimitsConfigError as exc:
        raise LimitsConfigError(f"{path}: {exc}") from exc
    chromium = raw.get("chromium")
    return Config(limits=limits, chromium=str(chromium) if chromium else None)
