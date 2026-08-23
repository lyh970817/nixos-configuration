"""The gate: the only way a request reaches a publisher through KCL.

Everything that could get the institution throttled or blocked is decided here,
in code, before the browser is allowed to navigate. The fetch path holds no
opinion of its own -- it calls `Gate.acquire()` and either gets an `Attempt` or
an exception, so there is no arrangement of arguments that fetches without
being counted.

Refusals are typed (`GateRefusal` subclasses) so a caller can tell "wait and
retry later" from "stop and talk to the library".

There is deliberately no batch entry point anywhere on this path. Not a
disabled one, not a hidden one -- the concept does not exist here, because
batch retrieval *is* the abuse signature.
"""

from __future__ import annotations

import fcntl
import re
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Sequence

from . import paths
from .limits import DEFAULTS, Limits

# --------------------------------------------------------------------------
# Refusals


class GateRefusal(RuntimeError):
    """Base class for every reason the gate said no."""

    #: Short machine-readable tag, also written to the ledger.
    kind = "refused"

    def advice(self) -> str:
        return str(self)


class BudgetExhausted(GateRefusal):
    kind = "budget"

    def __init__(self, message: str, retry_after: float):
        super().__init__(message)
        self.retry_after = retry_after

    def advice(self) -> str:
        mins = max(1, int(self.retry_after // 60))
        return f"{self} Wait about {mins} min, or use scansci-oa meanwhile."


class EnumerationSuspected(GateRefusal):
    kind = "enumeration"

    def advice(self) -> str:
        return (
            f"{self} Systematic issue/range retrieval is the pattern KCL's and "
            "the publishers' abuse policies name explicitly. Fetch individual "
            "articles you actually intend to read."
        )


class ConcurrencyRefused(GateRefusal):
    kind = "concurrency"

    def advice(self) -> str:
        return f"{self} Concurrency is fixed at 1 and is not configurable."


class PublisherBlocked(GateRefusal):
    kind = "blocked"

    def __init__(self, message: str, host: str, when: float, status: int | None):
        super().__init__(message)
        self.host = host
        self.when = when
        self.status = status

    def advice(self) -> str:
        return (
            f"{self} This is not retried automatically and must not be retried "
            "by hand. Contact the KCL library (libraryenquiries@kcl.ac.uk) and "
            "tell them the publisher host and the time; a block or an EZproxy "
            "UsageLimit trip is cleared by an administrator, not by waiting."
        )


# --------------------------------------------------------------------------
# Article identity


@dataclass(frozen=True)
class ArticleMeta:
    """What the enumeration detector needs. All of it optional."""

    journal: str | None = None
    volume: str | None = None
    issue: str | None = None

    def issue_key(self) -> str | None:
        if not (self.journal and self.volume and self.issue):
            return None
        return "|".join(
            part.strip().casefold() for part in (self.journal, self.volume, self.issue)
        )


_TRAILING_DIGITS = re.compile(r"^(?P<stem>.*?)(?P<number>\d+)$")


def _doi_run_key(doi: str) -> tuple[str, int] | None:
    """Split a DOI into (everything before the trailing number, the number).

    `10.1016/j.cell.2023.04.017` -> (`10.1016/j.cell.2023.04.`, 17). Two DOIs
    that share a stem and sit next to each other numerically are consecutive
    articles in the same publisher sequence.
    """
    m = _TRAILING_DIGITS.match(doi.strip().casefold())
    if not m or len(m.group("number")) > 9:
        return None
    return m.group("stem"), int(m.group("number"))


def _has_sequential_run(numbers: Iterable[int], threshold: int) -> bool:
    """True when `threshold` values form a near-consecutive run (gaps <= 2)."""
    ordered = sorted(set(numbers))
    if len(ordered) < threshold:
        return False
    run = 1
    for previous, current in zip(ordered, ordered[1:]):
        run = run + 1 if current - previous <= 2 else 1
        if run >= threshold:
            return True
    return False


# --------------------------------------------------------------------------
# Clock


class Clock:
    """Wall clock plus sleeping, injectable so tests never sleep for real."""

    def now(self) -> float:
        return time.time()

    def sleep(self, seconds: float) -> None:
        if seconds > 0:
            time.sleep(seconds)


# --------------------------------------------------------------------------
# Ledger

_SCHEMA = """
CREATE TABLE IF NOT EXISTS attempts (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    ts      REAL NOT NULL,
    host    TEXT NOT NULL,
    doi     TEXT NOT NULL,
    journal TEXT,
    volume  TEXT,
    issue   TEXT,
    outcome TEXT NOT NULL,
    detail  TEXT
);
CREATE INDEX IF NOT EXISTS attempts_ts ON attempts (ts);
CREATE TABLE IF NOT EXISTS blocks (
    host   TEXT PRIMARY KEY,
    ts     REAL NOT NULL,
    doi    TEXT,
    status INTEGER,
    detail TEXT
);
"""

#: Outcomes that mean a request actually left the machine, so they spend
#: budget. Refusals are still recorded -- they are the audit trail -- but they
#: cost nothing, or a refused fetch would push the next one further away.
SPENDING_OUTCOMES = ("pending", "ok", "miss", "blocked", "error")


class Gate:
    def __init__(
        self,
        *,
        db_path: Path,
        lock_path: Path,
        limits: Limits = DEFAULTS,
        clock: Clock | None = None,
    ):
        self.limits = limits
        self.clock = clock or Clock()
        self._lock_path = Path(lock_path)
        db_path = Path(db_path)
        paths.ensure(db_path.parent)
        paths.ensure(self._lock_path.parent)
        self.db = sqlite3.connect(str(db_path), isolation_level=None)
        # sqlite3 creates the file on connect, at 0666 & ~umask. Tightening it
        # before any schema runs also settles the journal, which SQLite creates
        # with the database file's own permissions.
        paths.secure_file(db_path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(_SCHEMA)

    def close(self) -> None:
        self.db.close()

    # -- queries ---------------------------------------------------------

    def _spending_since(self, since: float) -> int:
        placeholders = ",".join("?" * len(SPENDING_OUTCOMES))
        row = self.db.execute(
            f"SELECT COUNT(*) AS n FROM attempts WHERE ts >= ? "
            f"AND outcome IN ({placeholders})",
            (since, *SPENDING_OUTCOMES),
        ).fetchone()
        return int(row["n"])

    def _oldest_spending_since(self, since: float) -> float | None:
        placeholders = ",".join("?" * len(SPENDING_OUTCOMES))
        row = self.db.execute(
            f"SELECT MIN(ts) AS t FROM attempts WHERE ts >= ? "
            f"AND outcome IN ({placeholders})",
            (since, *SPENDING_OUTCOMES),
        ).fetchone()
        return None if row["t"] is None else float(row["t"])

    def _last_spending_ts(self, host: str | None = None) -> float | None:
        placeholders = ",".join("?" * len(SPENDING_OUTCOMES))
        sql = f"SELECT MAX(ts) AS t FROM attempts WHERE outcome IN ({placeholders})"
        params: list = list(SPENDING_OUTCOMES)
        if host is not None:
            sql += " AND host = ?"
            params.append(host)
        row = self.db.execute(sql, params).fetchone()
        return None if row["t"] is None else float(row["t"])

    def block_record(self, host: str) -> sqlite3.Row | None:
        return self.db.execute("SELECT * FROM blocks WHERE host = ?", (host,)).fetchone()

    def recent(self, limit: int = 20) -> Sequence[sqlite3.Row]:
        return self.db.execute(
            "SELECT * FROM attempts ORDER BY ts DESC LIMIT ?", (limit,)
        ).fetchall()

    def budget_state(self) -> dict:
        now = self.clock.now()
        lim = self.limits
        return {
            "short": (
                self._spending_since(now - lim.short_window_seconds),
                lim.short_window_max,
                lim.short_window_seconds,
            ),
            "long": (
                self._spending_since(now - lim.long_window_seconds),
                lim.long_window_max,
                lim.long_window_seconds,
            ),
        }

    # -- recording -------------------------------------------------------

    def _record(
        self,
        ts: float,
        host: str,
        doi: str,
        meta: ArticleMeta,
        outcome: str,
        detail: str | None = None,
    ) -> int:
        cur = self.db.execute(
            "INSERT INTO attempts (ts, host, doi, journal, volume, issue, outcome, detail)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (ts, host, doi, meta.journal, meta.volume, meta.issue, outcome, detail),
        )
        return int(cur.lastrowid)

    def record_refusal(
        self, host: str, doi: str, meta: ArticleMeta, refusal: GateRefusal
    ) -> None:
        self._record(
            self.clock.now(), host, doi, meta, f"refused:{refusal.kind}", str(refusal)
        )

    # -- checks ----------------------------------------------------------

    def _check_block(self, host: str) -> None:
        row = self.block_record(host)
        if row is None:
            return
        raise PublisherBlocked(
            f"{host} returned {row['status'] or 'a block'} at "
            f"{time.strftime('%Y-%m-%d %H:%M', time.localtime(row['ts']))} and is "
            "latched off.",
            host,
            float(row["ts"]),
            row["status"],
        )

    def _check_enumeration(self, now: float, doi: str, meta: ArticleMeta) -> None:
        lim = self.limits
        since = now - lim.enumeration_window_seconds
        rows = self.db.execute(
            "SELECT doi, journal, volume, issue FROM attempts WHERE ts >= ?", (since,)
        ).fetchall()

        candidate_issue = meta.issue_key()
        if candidate_issue is not None:
            seen = {doi.strip().casefold()}
            for row in rows:
                key = ArticleMeta(row["journal"], row["volume"], row["issue"]).issue_key()
                if key == candidate_issue:
                    seen.add(row["doi"].strip().casefold())
            if len(seen) >= lim.enumeration_issue_threshold:
                raise EnumerationSuspected(
                    f"{len(seen)} DOIs from {meta.journal} vol {meta.volume} "
                    f"issue {meta.issue} within "
                    f"{lim.enumeration_window_seconds / 3600:g}h -- that is "
                    "issue enumeration, not reading."
                )

        candidate_run = _doi_run_key(doi)
        if candidate_run is not None:
            stem, number = candidate_run
            numbers = [number]
            for row in rows:
                other = _doi_run_key(row["doi"])
                if other is not None and other[0] == stem:
                    numbers.append(other[1])
            if _has_sequential_run(numbers, lim.enumeration_sequential_threshold):
                raise EnumerationSuspected(
                    f"{doi} continues a run of consecutive DOI suffixes under "
                    f"{stem}* within {lim.enumeration_window_seconds / 3600:g}h -- "
                    "that is range walking."
                )

    def _check_budget(self, now: float) -> None:
        lim = self.limits
        for label, window, cap in (
            ("3-hour", lim.short_window_seconds, lim.short_window_max),
            ("daily", lim.long_window_seconds, lim.long_window_max),
        ):
            since = now - window
            used = self._spending_since(since)
            if used < cap:
                continue
            oldest = self._oldest_spending_since(since)
            retry_after = max(0.0, (oldest + window) - now) if oldest else window
            raise BudgetExhausted(
                f"{label} budget spent: {used}/{cap} fetches in the last "
                f"{window / 3600:g}h.",
                retry_after,
            )

    def _wait_for_slot(self, host: str) -> float:
        """Block until both the global spacing and the host cooldown are clear."""
        lim = self.limits
        while True:
            now = self.clock.now()
            waits = []
            last_any = self._last_spending_ts()
            if last_any is not None:
                waits.append(last_any + lim.global_min_interval - now)
            last_host = self._last_spending_ts(host)
            if last_host is not None:
                waits.append(last_host + lim.host_cooldown - now)
            wait = max(waits) if waits else 0.0
            if wait <= 0:
                return now
            self.clock.sleep(wait)

    # -- the gate itself -------------------------------------------------

    def acquire(self, host: str, doi: str, meta: ArticleMeta | None = None) -> "Attempt":
        """Admit exactly one request to `host` for `doi`, or refuse.

        Order matters: the latched block and the enumeration verdict are
        permanent-ish judgements, so they are answered before we spend any
        wall-clock waiting, and long before a browser exists.
        """
        meta = meta or ArticleMeta()
        host = host.strip().casefold()

        lock = _ProcessLock(self._lock_path)
        try:
            lock.acquire()
        except ConcurrencyRefused as refusal:
            self.record_refusal(host, doi, meta, refusal)
            raise

        try:
            self._check_block(host)
            self._check_enumeration(self.clock.now(), doi, meta)
            self._check_budget(self.clock.now())
            ts = self._wait_for_slot(host)
            # Re-check the budget after waiting: another window may have been
            # crossed, and the wait is the only place time moves inside acquire.
            self._check_budget(ts)
        except GateRefusal as refusal:
            self.record_refusal(host, doi, meta, refusal)
            lock.release()
            raise
        except BaseException:
            lock.release()
            raise

        row_id = self._record(ts, host, doi, meta, "pending")
        return Attempt(self, row_id, host, doi, meta, lock)


class Attempt:
    """One admitted request. Closing it writes the outcome to the ledger."""

    def __init__(
        self,
        gate: Gate,
        row_id: int,
        host: str,
        doi: str,
        meta: ArticleMeta,
        lock: "_ProcessLock",
    ):
        self.gate = gate
        self.row_id = row_id
        self.host = host
        self.doi = doi
        self.meta = meta
        self._lock = lock
        self._closed = False

    def __enter__(self) -> "Attempt":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        if not self._closed:
            self._finish("error" if exc_type else "miss", str(exc) if exc else None)
        return False

    def _finish(self, outcome: str, detail: str | None) -> None:
        self.gate.db.execute(
            "UPDATE attempts SET outcome = ?, detail = ? WHERE id = ?",
            (outcome, detail, self.row_id),
        )
        self._closed = True
        self._lock.release()

    def ok(self, detail: str | None = None) -> None:
        self._finish("ok", detail)

    def miss(self, detail: str | None = None) -> None:
        self._finish("miss", detail)

    def error(self, detail: str | None = None) -> None:
        self._finish("error", detail)

    def blocked(self, status: int | None = 403, detail: str | None = None) -> None:
        """Latch this host off. There is no automatic retry, by design."""
        self.gate.db.execute(
            "INSERT OR REPLACE INTO blocks (host, ts, doi, status, detail)"
            " VALUES (?, ?, ?, ?, ?)",
            (self.host, self.gate.clock.now(), self.doi, status, detail),
        )
        self._finish("blocked", detail)
        raise PublisherBlocked(
            f"{self.host} returned {status}.", self.host, self.gate.clock.now(), status
        )


class _ProcessLock:
    """Concurrency 1, enforced by the kernel rather than by intent.

    `flock` is held by the open file description, so two `Gate`s in one process
    contend exactly as two processes do -- which is what makes this testable
    and what makes a second `kcl-fetch` refuse rather than double up.
    """

    def __init__(self, path: Path):
        self.path = Path(path)
        self._fh = None

    def acquire(self) -> None:
        self._fh = open(self.path, "a+")
        paths.secure_file(self.path)
        try:
            fcntl.flock(self._fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self._fh.close()
            self._fh = None
            raise ConcurrencyRefused(
                "another kcl-fetch is already fetching."
            ) from None

    def release(self) -> None:
        if self._fh is None:
            return
        try:
            fcntl.flock(self._fh.fileno(), fcntl.LOCK_UN)
        finally:
            self._fh.close()
            self._fh = None
