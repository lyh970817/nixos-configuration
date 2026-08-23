"""The CLI surface: what it offers, and how it picks an ozone platform."""

from __future__ import annotations

import os
import unittest
from unittest import mock

import kcl_fetch


class TestOzoneArgs(unittest.TestCase):
    """chromium 144 defaults to Wayland; over SSH there is no Wayland to use."""

    def test_absent_wayland_display_falls_back_to_x11(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(kcl_fetch._ozone_args(None), ("--ozone-platform=x11",))

    def test_an_empty_wayland_display_is_treated_as_absent(self):
        with mock.patch.dict(os.environ, {"WAYLAND_DISPLAY": ""}, clear=True):
            self.assertEqual(kcl_fetch._ozone_args(None), ("--ozone-platform=x11",))

    def test_a_wayland_session_is_left_to_chromiums_own_choice(self):
        with mock.patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-1"}, clear=True):
            self.assertEqual(kcl_fetch._ozone_args(None), ())

    def test_an_explicit_platform_wins_over_the_environment(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(
                kcl_fetch._ozone_args("wayland"), ("--ozone-platform=wayland",)
            )
        with mock.patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-1"}, clear=True):
            self.assertEqual(kcl_fetch._ozone_args("x11"), ("--ozone-platform=x11",))


class TestParser(unittest.TestCase):
    def setUp(self) -> None:
        self.parser = kcl_fetch.build_parser()

    def test_the_browser_subcommands_accept_ozone_platform(self):
        self.assertEqual(
            self.parser.parse_args(["login", "--ozone-platform", "x11"]).ozone_platform,
            "x11",
        )
        self.assertEqual(
            self.parser.parse_args(["get", "10.1000/x"]).ozone_platform, None
        )

    def test_there_is_no_batch_subcommand(self):
        """Bulk retrieval is the abuse signature; its absence is the feature."""
        actions = [
            a
            for a in self.parser._subparsers._group_actions
            if hasattr(a, "choices") and a.choices
        ]
        offered = set()
        for action in actions:
            offered.update(action.choices)
        self.assertEqual(offered, {"get", "login", "status"})


if __name__ == "__main__":
    unittest.main()
