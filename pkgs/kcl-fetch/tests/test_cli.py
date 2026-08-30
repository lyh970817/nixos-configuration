"""The CLI surface: what it offers, and how it reports the display it picked.

The resolution itself lives in `test_display.py`; what is checked here is that
the CLI asks for it, passes the answer on, and says so under `--verbose`.
"""

from __future__ import annotations

import argparse
import unittest
from unittest import mock

import kcl_fetch
from kcl_fetch_lib import display as display_mod


class TestDisplayReporting(unittest.TestCase):
    def _args(self, **kwargs):
        return argparse.Namespace(
            **{"ozone_platform": None, "verbose": False, **kwargs}
        )

    def test_the_resolved_display_is_handed_back_untouched(self):
        chosen = display_mod.Display("wayland", {"WAYLAND_DISPLAY": "wayland-1"}, "d")
        with mock.patch.object(display_mod, "resolve", return_value=chosen) as resolve:
            self.assertIs(kcl_fetch._display(self._args()), chosen)
        resolve.assert_called_once_with(None)

    def test_an_explicit_platform_is_forwarded_to_the_resolver(self):
        chosen = display_mod.Display("x11", {}, "forced")
        with mock.patch.object(display_mod, "resolve", return_value=chosen) as resolve:
            kcl_fetch._display(self._args(ozone_platform="x11"))
        resolve.assert_called_once_with("x11")

    def test_verbose_names_the_platform_and_the_exported_variables(self):
        chosen = display_mod.Display(
            "wayland",
            {"WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": "/run/user/1000"},
            "wayland socket /run/user/1000/wayland-1",
        )
        with mock.patch.object(display_mod, "resolve", return_value=chosen):
            with mock.patch("sys.stderr", new_callable=_Capture) as err:
                kcl_fetch._display(self._args(verbose=True))
        self.assertIn("wayland socket /run/user/1000/wayland-1", err.text)
        self.assertIn("WAYLAND_DISPLAY=wayland-1", err.text)
        self.assertIn("XDG_RUNTIME_DIR=/run/user/1000", err.text)

    def test_quiet_by_default(self):
        chosen = display_mod.Display("wayland", {}, "d")
        with mock.patch.object(display_mod, "resolve", return_value=chosen):
            with mock.patch("sys.stderr", new_callable=_Capture) as err:
                kcl_fetch._display(self._args())
        self.assertEqual(err.text, "")


class _Capture:
    def __init__(self) -> None:
        self.text = ""

    def write(self, chunk: str) -> int:
        self.text += chunk
        return len(chunk)

    def flush(self) -> None:
        pass


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

    def test_the_browser_subcommands_accept_verbose(self):
        self.assertTrue(self.parser.parse_args(["login", "--verbose"]).verbose)
        self.assertFalse(self.parser.parse_args(["get", "10.1000/x"]).verbose)

    def test_get_takes_a_timeout_for_the_human_at_the_window(self):
        """`get` had none: a challenge it told the user to answer by hand."""
        self.assertEqual(
            self.parser.parse_args(["get", "10.1000/x"]).timeout,
            kcl_fetch.INTERACTIVE_TIMEOUT,
        )
        self.assertEqual(
            self.parser.parse_args(["get", "10.1000/x", "--timeout", "60"]).timeout,
            60.0,
        )

    def test_it_is_the_same_wait_login_gives_a_human(self):
        """Both are "how long until a person walks to the machine"."""
        self.assertEqual(
            self.parser.parse_args(["login"]).timeout,
            self.parser.parse_args(["get", "10.1000/x"]).timeout,
        )

    def test_the_default_is_long_enough_to_walk_to_another_room(self):
        self.assertGreaterEqual(kcl_fetch.INTERACTIVE_TIMEOUT, 300.0)

    def test_show_is_no_longer_advertised_as_a_spectator_flag(self):
        help_text = _get_help(self.parser)
        self.assertIn("waits", help_text)
        # The reason it costs nothing is still worth saying.
        self.assertIn("publisher can see", help_text)

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


def _get_help(parser) -> str:
    """The `get` subparser's own help text, without exiting the process."""
    for action in parser._subparsers._group_actions:
        choices = getattr(action, "choices", None) or {}
        if "get" in choices:
            return choices["get"].format_help()
    raise AssertionError("no get subparser")


if __name__ == "__main__":
    unittest.main()
