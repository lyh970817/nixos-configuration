"""Ordered base-URL resolution for Anna's Archive.

Mirrors come and go. Measured 2026-08: ``.gd`` and ``.gl`` answer
``/dyn/api/*``; ``.org``, ``.se``, ``.in`` and ``.pm`` fail the TLS handshake.
Resolution walks the list in order, keeps the first mirror that answers, and
caches it so the next invocation does not re-probe the dead ones.
"""

from __future__ import annotations

import json
import time
from pathlib import Path

#: Ordered by observed reliability. A mirror that stops answering is skipped,
#: not removed -- they recover.
DEFAULT_BASES = (
    "https://annas-archive.gd",
    "https://annas-archive.gl",
    "https://annas-archive.se",
    "https://annas-archive.org",
)

#: Probing with no parameters costs nothing: a live mirror answers 400 with the
#: API's own usage document, so any HTTP status at all means "alive".
PROBE_PATH = "/dyn/api/fast_download.json"

CACHE_TTL_SECONDS = 24 * 3600


class NoMirrorError(RuntimeError):
    """Raised when no configured mirror answered."""


def read_cache(path: Path, *, ttl: float = CACHE_TTL_SECONDS, now: float | None = None) -> str | None:
    now = time.time() if now is None else now
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    base = data.get("base")
    ts = data.get("ts", 0)
    if not isinstance(base, str) or not base:
        return None
    if not isinstance(ts, (int, float)) or now - ts > ttl:
        return None
    return base


def write_cache(path: Path, base: str, *, now: float | None = None) -> None:
    now = time.time() if now is None else now
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"base": base, "ts": now}), encoding="utf-8")
    except OSError:
        pass  # a cache that cannot be written is not an error


def resolve_base(
    probe,
    *,
    bases=DEFAULT_BASES,
    cache_path: Path | None = None,
    ttl: float = CACHE_TTL_SECONDS,
    now: float | None = None,
) -> str:
    """Return the first base URL for which ``probe(base)`` is true.

    A cached base is tried first but is still probed, so a mirror that died
    since it was cached fails over to the next one instead of hanging.
    """
    ordered = list(bases)
    cached = read_cache(cache_path, ttl=ttl, now=now) if cache_path else None
    if cached:
        ordered = [cached] + [b for b in ordered if b != cached]

    for base in ordered:
        if probe(base):
            if cache_path and base != cached:
                write_cache(cache_path, base, now=now)
            return base

    raise NoMirrorError(
        "no Anna's Archive mirror answered: tried " + ", ".join(ordered)
    )
