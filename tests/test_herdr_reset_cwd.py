#!/usr/bin/env python3

from __future__ import annotations

import copy
import importlib.util
import json
import os
import socket
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("herdr_reset_cwd", ROOT / "scripts/herdr-reset-cwd.py")
assert SPEC and SPEC.loader
RESET = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RESET)

# A version 3 snapshot with the fields the user expects to survive: a custom
# tab name, an agent session ref, a split layout, zoom/focus state, and a
# second workspace whose identity_cwd differs from its pane cwd.
SNAPSHOT = {
    "version": 3,
    "workspaces": [
        {
            "id": "w1E",
            "custom_name": None,
            "identity_cwd": "/home/andongni/.nixos-config",
            "public_pane_numbers": {"2": 1},
            "next_public_pane_number": 2,
            "public_tab_numbers": [1],
            "next_public_tab_number": 2,
            "tabs": [
                {
                    "custom_name": "Reset directory to home after server reboot",
                    "layout": {
                        "Split": {
                            "direction": "Vertical",
                            "ratio": 0.5,
                            "first": {"Pane": 2},
                            "second": {"Pane": 4},
                        }
                    },
                    "panes": {
                        "2": {
                            "cwd": "/home/andongni/.nixos-config",
                            "agent_session": {
                                "source": "herdr:claude",
                                "agent": "claude",
                                "kind": "id",
                                "value": "81538cbf-2449-4c13-a38f-db6c011b0bfa",
                            },
                        },
                        "4": {"cwd": "/tmp/scratch", "label": "notes"},
                    },
                    "zoomed": True,
                    "focused": 2,
                    "root_pane": 2,
                }
            ],
            "active_tab": 0,
        },
        {
            "id": "w1F",
            "custom_name": "笔记",
            "identity_cwd": "/srv/data",
            "public_pane_numbers": {"3": 1},
            "next_public_pane_number": 2,
            "public_tab_numbers": [1],
            "next_public_tab_number": 2,
            "tabs": [
                {
                    "custom_name": None,
                    "layout": {"Pane": 3},
                    "panes": {"3": {"cwd": "/var/log"}},
                    "zoomed": False,
                    "focused": 3,
                    "root_pane": 3,
                }
            ],
            "active_tab": 0,
        },
    ],
    "active": 1,
    "selected": 1,
    "sidebar_width": 26,
    "sidebar_section_split": 0.5,
    "collapsed_space_keys": [],
}

HOME = "/home/tester"
LONG_AGO = 1_000_000_000  # comfortably before any plausible boot


def strip_cwds(node):
    """Blank every cwd-ish field so the rest of the tree can be compared."""
    if isinstance(node, dict):
        return {k: ("" if k in RESET.CWD_KEYS else strip_cwds(v)) for k, v in node.items()}
    if isinstance(node, list):
        return [strip_cwds(v) for v in node]
    return node


def collect_cwds(node, found=None):
    found = [] if found is None else found
    if isinstance(node, dict):
        for key, value in node.items():
            if key in RESET.CWD_KEYS:
                found.append(value)
            else:
                collect_cwds(value, found)
    elif isinstance(node, list):
        for value in node:
            collect_cwds(value, found)
    return found


class Listener:
    """A real AF_UNIX listener, so the guard is exercised, not mocked."""

    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(str(path))
        self.sock.listen(1)
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            conn.close()

    def close(self):
        self.sock.close()
        self.thread.join(timeout=2)


class ResetTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        self.path = self.dir / "session.json"

    def write_snapshot(self, snapshot=SNAPSHOT, aged=True):
        self.path.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False), encoding="utf-8")
        if aged:
            os.utime(self.path, (LONG_AGO, LONG_AGO))
        return self.path.read_bytes()

    def leftovers(self):
        return [p.name for p in self.dir.iterdir() if p.name != "session.json"]

    def test_every_cwd_becomes_home_and_nothing_else_moves(self):
        self.write_snapshot()
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn("reset 5 directories", report)

        result = json.loads(self.path.read_text(encoding="utf-8"))
        self.assertEqual(collect_cwds(result), [HOME] * 5)
        self.assertEqual(strip_cwds(result), strip_cwds(SNAPSHOT))

    def test_layout_names_and_agent_session_survive(self):
        self.write_snapshot()
        RESET.reset_session(self.dir, HOME)
        result = json.loads(self.path.read_text(encoding="utf-8"))

        self.assertEqual(result["version"], 3)
        tab = result["workspaces"][0]["tabs"][0]
        self.assertEqual(tab["custom_name"], "Reset directory to home after server reboot")
        self.assertEqual(tab["layout"], SNAPSHOT["workspaces"][0]["tabs"][0]["layout"])
        self.assertEqual(tab["focused"], 2)
        self.assertTrue(tab["zoomed"])
        self.assertEqual(
            tab["panes"]["2"]["agent_session"],
            SNAPSHOT["workspaces"][0]["tabs"][0]["panes"]["2"]["agent_session"],
        )
        self.assertEqual(tab["panes"]["4"]["label"], "notes")
        self.assertEqual(result["workspaces"][1]["custom_name"], "笔记")

    def test_output_matches_herdr_own_formatting(self):
        self.write_snapshot()
        RESET.reset_session(self.dir, HOME)
        expected = copy.deepcopy(SNAPSHOT)
        RESET.rewrite(expected, HOME)
        self.assertEqual(
            self.path.read_text(encoding="utf-8"),
            json.dumps(expected, indent=2, ensure_ascii=False),
        )

    def test_missing_file_is_a_clean_no_op(self):
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn("no snapshot", report)
        self.assertFalse(self.path.exists())
        self.assertEqual(self.leftovers(), [])

    def test_corrupt_file_is_left_byte_for_byte(self):
        corrupt = b'{"version": 3, "workspaces": [{"cwd": '
        self.path.write_bytes(corrupt)
        os.utime(self.path, (LONG_AGO, LONG_AGO))
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn("unparseable", report)
        self.assertEqual(self.path.read_bytes(), corrupt)
        self.assertEqual(self.leftovers(), [])

    def test_non_object_snapshot_is_left_alone(self):
        self.path.write_text("[1, 2, 3]", encoding="utf-8")
        os.utime(self.path, (LONG_AGO, LONG_AGO))
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn("not a snapshot object", report)
        self.assertEqual(self.path.read_text(encoding="utf-8"), "[1, 2, 3]")

    def test_live_server_is_never_clobbered(self):
        original = self.write_snapshot()
        listener = Listener(self.dir / "herdr.sock")
        self.addCleanup(listener.close)
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn("server is live", report)
        self.assertEqual(self.path.read_bytes(), original)

    def test_stale_socket_does_not_block_the_reset(self):
        self.write_snapshot()
        # A dead herdr leaves a real socket file behind, so the guard has to
        # connect rather than trust that the path exists.
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(str(self.dir / "herdr.sock"))
        stale.close()
        self.assertTrue((self.dir / "herdr.sock").exists())
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn("reset 5 directories", report)

    def test_snapshot_from_this_boot_is_left_alone(self):
        original = self.write_snapshot(aged=False)
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn("written during this boot", report)
        self.assertEqual(self.path.read_bytes(), original)

    def test_force_overrides_the_boot_check_but_not_the_live_server_check(self):
        self.write_snapshot(aged=False)
        self.assertIn("reset 5 directories", RESET.reset_session(self.dir, HOME, force=True))

        original = self.write_snapshot(aged=False)
        listener = Listener(self.dir / "herdr.sock")
        self.addCleanup(listener.close)
        self.assertIn("server is live", RESET.reset_session(self.dir, HOME, force=True))
        self.assertEqual(self.path.read_bytes(), original)

    def test_rerun_is_idempotent_and_does_not_rewrite(self):
        self.write_snapshot()
        RESET.reset_session(self.dir, HOME)
        os.utime(self.path, (LONG_AGO, LONG_AGO))
        before = self.path.stat().st_mtime_ns
        report = RESET.reset_session(self.dir, HOME)
        self.assertIn(f"already at {HOME}", report)
        self.assertEqual(self.path.stat().st_mtime_ns, before)

    def test_file_mode_is_preserved(self):
        self.write_snapshot()
        os.chmod(self.path, 0o600)
        os.utime(self.path, (LONG_AGO, LONG_AGO))
        RESET.reset_session(self.dir, HOME)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)


class SessionDiscoveryTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "herdr"
        self.root.mkdir()
        self.addCleanup(self.tmp.cleanup)

    def test_named_sessions_are_treated_like_the_default_one(self):
        for name in ("remote", "wave1-ecf55cea"):
            (self.root / "sessions" / name).mkdir(parents=True)
        (self.root / "sessions" / "stray.txt").write_text("", encoding="utf-8")

        self.assertEqual(
            RESET.session_dirs(self.root),
            [
                self.root,
                self.root / "sessions" / "remote",
                self.root / "sessions" / "wave1-ecf55cea",
            ],
        )

    def test_missing_sessions_directory_is_fine(self):
        self.assertEqual(RESET.session_dirs(self.root), [self.root])

    def test_main_walks_every_session(self):
        for name in ("remote", "other"):
            directory = self.root / "sessions" / name
            directory.mkdir(parents=True)
            path = directory / "session.json"
            path.write_text(json.dumps(SNAPSHOT), encoding="utf-8")
            os.utime(path, (LONG_AGO, LONG_AGO))

        env = {"XDG_CONFIG_HOME": str(self.root.parent), "HOME": HOME}
        with mock.patch.dict(os.environ, env, clear=False):
            self.assertEqual(RESET.main([]), 0)

        for name in ("remote", "other"):
            result = json.loads((self.root / "sessions" / name / "session.json").read_text())
            self.assertEqual(collect_cwds(result), [HOME] * 5)

    def test_config_dir_follows_xdg_config_home(self):
        with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": "/x/cfg"}, clear=False):
            self.assertEqual(RESET.config_dir(), Path("/x/cfg/herdr"))
        env = dict(os.environ)
        env.pop("XDG_CONFIG_HOME", None)
        with mock.patch.dict(os.environ, env, clear=True):
            with mock.patch.object(Path, "home", staticmethod(lambda: Path("/h/u"))):
                self.assertEqual(RESET.config_dir(), Path("/h/u/.config/herdr"))


if __name__ == "__main__":
    unittest.main()
