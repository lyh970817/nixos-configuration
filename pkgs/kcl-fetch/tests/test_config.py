"""The config file is a one-way valve onto the shipped limits."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from kcl_fetch_lib.config import load
from kcl_fetch_lib.limits import DEFAULTS, LimitsConfigError


class TestConfig(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "config.json"
        self.addCleanup(self._tmp.cleanup)

    def write(self, payload) -> Path:
        self.path.write_text(
            payload if isinstance(payload, str) else json.dumps(payload),
            encoding="utf-8",
        )
        return self.path

    def test_an_absent_config_yields_the_shipped_defaults(self):
        self.assertEqual(load(self.path).limits, DEFAULTS)

    def test_a_tightening_config_is_applied(self):
        cfg = load(self.write({"limits": {"short_window_max": 5}}))
        self.assertEqual(cfg.limits.short_window_max, 5)

    def test_a_loosening_config_is_rejected_outright(self):
        for limits in (
            {"short_window_max": 500},
            {"long_window_max": 1000},
            {"global_min_interval": 0.05},
            {"host_cooldown": 0},
            {"enumeration_issue_threshold": 50},
        ):
            with self.subTest(limits=limits):
                with self.assertRaises(LimitsConfigError):
                    load(self.write({"limits": limits}))

    def test_concurrency_cannot_be_configured_at_all(self):
        with self.assertRaises(LimitsConfigError):
            load(self.write({"limits": {"concurrency": 4}}))
        with self.assertRaises(LimitsConfigError):
            load(self.write({"concurrency": 4}))

    def test_unknown_top_level_keys_are_rejected(self):
        with self.assertRaises(LimitsConfigError):
            load(self.write({"batch": True}))

    def test_broken_json_is_an_error_not_a_silent_default(self):
        # Falling back to the defaults would be safe, but it would also hide a
        # config the user believes is tightening things.
        with self.assertRaises(LimitsConfigError):
            load(self.write("{nope"))

    def test_a_chromium_override_is_carried_through(self):
        cfg = load(self.write({"chromium": "/run/current-system/sw/bin/chromium"}))
        self.assertEqual(cfg.chromium, "/run/current-system/sw/bin/chromium")


if __name__ == "__main__":
    unittest.main()
