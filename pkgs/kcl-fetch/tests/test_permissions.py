"""Modes are set, never inherited.

The bug this pins down was observed, not imagined: run from a non-interactive
SSH shell (umask 022), `paths.ensure()` produced a 0755 state directory and a
0644 ledger, where the same code from an interactive shell produced 0700/0600.
The profile directory is the one that matters -- it holds the institutional SSO
session -- so every test here sets a deliberately permissive umask first and
then insists on 0700/0600 anyway.

Repair is in place. A directory that already exists is chmodded, never removed
and recreated: doing that to the profile would throw away a live session, and
`rm` is not how this repository deletes things.
"""

from __future__ import annotations

import os
import sqlite3
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from support import FakeClock

from kcl_fetch_lib import paths, routing
from kcl_fetch_lib.gate import Gate

#: Loose enough to reveal the bug: 0777 & ~022 is 0755, 0666 & ~022 is 0644.
LOOSE_UMASK = 0o022


def mode_of(path: Path) -> int:
    return stat.S_IMODE(path.stat().st_mode)


class XdgCase(unittest.TestCase):
    """Every path under a throwaway root, so the real ~/.local is never touched."""

    umask = LOOSE_UMASK

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)

        previous = os.umask(self.umask)
        self.addCleanup(os.umask, previous)

        env = mock.patch.dict(
            os.environ,
            {
                "XDG_STATE_HOME": str(self.root / "state"),
                "XDG_DATA_HOME": str(self.root / "data"),
                "XDG_CONFIG_HOME": str(self.root / "config"),
            },
        )
        env.start()
        self.addCleanup(env.stop)

    def assertOwnerOnly(self, path: Path, mode: int) -> None:
        self.assertEqual(mode_of(path), mode, f"{path} is {oct(mode_of(path))}")
        self.assertFalse(mode_of(path) & (stat.S_IRWXG | stat.S_IRWXO))

    def gate(self, db_path: Path | None = None, lock_path: Path | None = None) -> Gate:
        """A gate on the fake clock, so no test ever waits out a cooldown."""
        gate = Gate(
            db_path=paths.ledger_path() if db_path is None else db_path,
            lock_path=paths.lock_path() if lock_path is None else lock_path,
            clock=FakeClock(),
        )
        self.addCleanup(gate.close)
        return gate


class TestFreshCreation(XdgCase):
    def test_the_state_directory_is_0700_despite_the_umask(self):
        self.assertOwnerOnly(paths.ensure(paths.state_dir()), 0o700)

    def test_the_profile_directory_is_0700_despite_the_umask(self):
        # The credential store. This is the one that must not be 0755.
        self.assertOwnerOnly(paths.ensure(paths.profile_dir()), 0o700)

    def test_a_nested_directory_and_its_app_root_are_both_0700(self):
        downloads = paths.ensure(paths.state_dir() / "downloads")
        self.assertOwnerOnly(downloads, 0o700)
        self.assertOwnerOnly(paths.state_dir(), 0o700)

    def test_directories_above_the_app_root_are_left_to_the_user(self):
        """`~/.local/state` is not ours to tighten -- only `.../kcl-fetch` is."""
        paths.ensure(paths.state_dir())
        self.assertEqual(mode_of(self.root / "state"), 0o777 & ~LOOSE_UMASK)

    def test_the_ledger_and_lock_files_are_0600_despite_the_umask(self):
        with self.gate().acquire("nature.com", "10.1000/x") as attempt:
            attempt.ok()
        self.assertOwnerOnly(paths.ledger_path(), 0o600)
        self.assertOwnerOnly(paths.lock_path(), 0o600)

    def test_the_routing_cache_is_0600_despite_the_umask(self):
        table = routing.RoutingTable(paths.routes_path())
        table.record("nature.com", "ezproxy", worked=True)
        self.assertOwnerOnly(paths.routes_path(), 0o600)

    def test_no_stray_world_readable_temp_file_is_left_behind(self):
        table = routing.RoutingTable(paths.routes_path())
        table.record("nature.com", "ezproxy", worked=True)
        leftovers = [p for p in paths.state_dir().iterdir() if p.suffix == ".tmp"]
        self.assertEqual(leftovers, [])


class TestRepairInPlace(XdgCase):
    def test_an_existing_0755_state_directory_is_repaired_and_keeps_its_contents(self):
        state = paths.state_dir()
        state.mkdir(parents=True)
        os.chmod(state, 0o755)
        sentinel = state / "ledger.sqlite3"
        sentinel.write_text("not really a database", encoding="utf-8")
        before = state.stat().st_ino

        paths.ensure(state)

        self.assertOwnerOnly(state, 0o700)
        self.assertEqual(state.stat().st_ino, before, "the directory was recreated")
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "not really a database")

    def test_an_existing_0755_profile_is_repaired_without_disturbing_the_session(self):
        profile = paths.profile_dir()
        profile.mkdir(parents=True)
        os.chmod(profile, 0o755)
        cookies = profile / "Cookies"
        cookies.write_bytes(b"SQLite format 3\x00")
        os.chmod(cookies, 0o644)
        before = profile.stat().st_ino

        paths.ensure(profile)

        self.assertOwnerOnly(profile, 0o700)
        self.assertEqual(profile.stat().st_ino, before)
        self.assertEqual(cookies.read_bytes(), b"SQLite format 3\x00")
        # Chromium's own files stay Chromium's business; 0700 on the containing
        # directory is the boundary, so nothing recurses into the profile.
        self.assertEqual(mode_of(cookies), 0o644)

    def test_the_app_root_is_repaired_when_only_a_child_is_ensured(self):
        state = paths.state_dir()
        state.mkdir(parents=True)
        os.chmod(state, 0o755)
        paths.ensure(state / "downloads")
        self.assertOwnerOnly(state, 0o700)

    def test_an_existing_0644_ledger_is_repaired_and_keeps_its_rows(self):
        first = self.gate()
        with first.acquire("nature.com", "10.1000/x") as attempt:
            attempt.ok()
        first.close()
        os.chmod(paths.ledger_path(), 0o644)

        second = self.gate()

        self.assertOwnerOnly(paths.ledger_path(), 0o600)
        rows = second.db.execute("SELECT doi FROM attempts").fetchall()
        self.assertEqual([row["doi"] for row in rows], ["10.1000/x"])

    def test_an_existing_0644_routing_cache_is_repaired_on_the_next_write(self):
        paths.ensure(paths.state_dir())
        routes = paths.routes_path()
        routes.write_text('{"hosts": {"nature.com": "ezproxy"}}', encoding="utf-8")
        os.chmod(routes, 0o644)

        table = routing.RoutingTable(routes)
        table.record("science.org", "ezproxy", worked=True)

        self.assertOwnerOnly(routes, 0o600)
        self.assertEqual(table.preferred("nature.com"), "ezproxy")


class TestAlreadyCorrectIsANoOp(XdgCase):
    """Nothing to fix must mean no `chmod` at all, not a harmless repeat."""

    def chmod_calls(self, action) -> list:
        with mock.patch.object(os, "chmod", wraps=os.chmod) as chmod:
            action()
            return chmod.call_args_list

    def test_ensuring_an_already_0700_directory_issues_no_chmod(self):
        state = paths.ensure(paths.state_dir())
        self.assertEqual(self.chmod_calls(lambda: paths.ensure(state)), [])
        self.assertOwnerOnly(state, 0o700)

    def test_securing_an_already_0600_file_issues_no_chmod(self):
        paths.ensure(paths.state_dir())
        ledger = paths.ledger_path()
        ledger.write_text("x", encoding="utf-8")
        os.chmod(ledger, 0o600)
        self.assertEqual(self.chmod_calls(lambda: paths.secure_file(ledger)), [])
        self.assertOwnerOnly(ledger, 0o600)

    def test_reopening_a_correct_ledger_changes_nothing(self):
        self.gate().close()
        before = paths.ledger_path().stat()

        calls = self.chmod_calls(lambda: self.gate())

        self.assertEqual(calls, [])
        self.assertEqual(mode_of(paths.ledger_path()), stat.S_IMODE(before.st_mode))

    def test_set_mode_reports_whether_it_changed_anything(self):
        state = paths.ensure(paths.state_dir())
        self.assertFalse(paths.set_mode(state, 0o700))
        os.chmod(state, 0o755)
        self.assertTrue(paths.set_mode(state, 0o700))

    def test_securing_a_file_that_does_not_exist_is_not_an_error(self):
        missing = paths.state_dir() / "never-written"
        self.assertEqual(self.chmod_calls(lambda: paths.secure_file(missing)), [])
        self.assertFalse(missing.exists())


class TestSqliteJournalInheritsTheLedgerMode(XdgCase):
    """A hot journal is a copy of ledger rows; it must not be the loose one."""

    def test_a_journal_left_by_an_interrupted_write_is_not_world_readable(self):
        gate = self.gate()
        gate.db.execute("BEGIN")
        gate.db.execute(
            "INSERT INTO attempts (ts, host, doi, outcome) VALUES (?, ?, ?, ?)",
            (0.0, "nature.com", "10.1000/x", "ok"),
        )
        journals = [p for p in paths.state_dir().iterdir() if "journal" in p.name]
        try:
            for journal in journals:
                self.assertFalse(mode_of(journal) & (stat.S_IRWXG | stat.S_IRWXO))
        finally:
            gate.db.execute("ROLLBACK")
        self.assertTrue(journals, "expected sqlite to leave a rollback journal")


def pdf_bytes(pages: int = 14, padding: int = 4096) -> bytes:
    """A file plausible enough for `pdfcheck.validate` to accept."""
    body = b"%PDF-1.7\n1 0 obj\n<< /Type /Pages /Kids [] /Count "
    body += str(pages).encode("ascii") + b" >>\nendobj\n"
    return body + b"%" + b"x" * padding + b"\n%%EOF\n"


class FakeDownload:
    def save_as(self, path: str) -> None:
        Path(path).write_bytes(pdf_bytes())


class FakeExpect:
    def __enter__(self):
        return self

    def __exit__(self, *exc) -> bool:
        return False

    value = FakeDownload()


class FakePage:
    """Enough of a Playwright page to walk `fetch_pdf` to the sidecar."""

    url = "https://publisher.example/doi/epdf/10.1000/x.pdf"

    def goto(self, url, **kwargs):
        return type("Response", (), {"status": 200})()

    def inner_text(self, selector, **kwargs) -> str:
        return "Abstract"

    def expect_download(self, **kwargs) -> FakeExpect:
        return FakeExpect()

    def reload(self) -> None:
        pass


class TestFilesWrittenIntoTheOutputDirectory(XdgCase):
    """The PDF and its sidecar are ours; the directory holding them is not."""

    def fetch(self, out_dir: Path):
        from kcl_fetch_lib import driver as driver_mod

        browser = driver_mod.Browser(
            profile_dir=paths.profile_dir(),
            chromium="/nonexistent/chromium",
            downloads_dir=paths.state_dir() / "downloads",
        )
        browser.context = type("Context", (), {"pages": [FakePage()]})()
        return browser.fetch_pdf(
            "https://go.openathens.net/redirector/kcl.ac.uk?url=x",
            doi="10.1000/x",
            template="openathens",
            out_dir=out_dir,
            stem="10.1000_x",
            min_bytes=1024,
        )

    def test_the_pdf_and_the_provenance_sidecar_are_0600(self):
        out_dir = self.root / "papers"
        result = self.fetch(out_dir)
        self.assertOwnerOnly(result.path, 0o600)
        self.assertOwnerOnly(result.path.with_suffix(".provenance.json"), 0o600)

    def test_the_users_output_directory_keeps_its_own_mode(self):
        out_dir = self.root / "papers"
        self.fetch(out_dir)
        self.assertEqual(mode_of(out_dir), 0o777 & ~LOOSE_UMASK)


class TestNoRegressionInOrdinaryUse(XdgCase):
    """The hardening must not change what the files actually contain."""

    def test_a_gate_over_a_caller_supplied_directory_still_works(self):
        # `Gate` is constructed with explicit paths in production and in tests;
        # a directory outside the XDG roots must not send `ensure` walking up.
        elsewhere = self.root / "elsewhere" / "deep"
        gate = self.gate(elsewhere / "ledger.sqlite3", elsewhere / "lock")
        with gate.acquire("nature.com", "10.1000/x") as attempt:
            attempt.ok()
        self.assertOwnerOnly(elsewhere, 0o700)
        # The parent it had to create on the way is not ours to tighten.
        self.assertEqual(mode_of(self.root / "elsewhere"), 0o777 & ~LOOSE_UMASK)
        self.assertIsInstance(gate.db, sqlite3.Connection)


if __name__ == "__main__":
    unittest.main()
