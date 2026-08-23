"""Test scaffolding: a clock that never sleeps and a gate wired to tmpdirs."""

from __future__ import annotations

import tempfile
from pathlib import Path

from kcl_fetch_lib.gate import Clock, Gate
from kcl_fetch_lib.limits import DEFAULTS


class FakeClock(Clock):
    """Wall time under test control. `sleep` advances it instead of blocking."""

    def __init__(self, start: float = 1_700_000_000.0):
        self.t = start
        self.slept: list[float] = []

    def now(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        if seconds > 0:
            self.slept.append(seconds)
            self.t += seconds

    def advance(self, seconds: float) -> None:
        self.t += seconds


class GateFixture:
    """A Gate over a throwaway directory, plus its clock."""

    def __init__(self, limits=DEFAULTS):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.clock = FakeClock()
        self.limits = limits
        self.gate = self._make()

    def _make(self) -> Gate:
        return Gate(
            db_path=self.root / "ledger.sqlite3",
            lock_path=self.root / "fetch.lock",
            limits=self.limits,
            clock=self.clock,
        )

    def second_gate(self) -> Gate:
        """A separate Gate over the same files -- stands in for a second process.

        `flock` is owned by the open file description, so two opens contend
        exactly as two processes do.
        """
        return self._make()

    def fetch(self, host: str, doi: str, meta=None, outcome: str = "ok") -> None:
        """One complete admitted request, so budgets and cooldowns advance."""
        with self.gate.acquire(host, doi, meta) as attempt:
            getattr(attempt, outcome)()

    def close(self) -> None:
        self.gate.close()
        self._tmp.cleanup()
