"""Display resolution: sockets on disk beat variables in the environment.

The regression these guard is a real one. On a healthy Hyprland desktop,
`kcl-fetch login` was run from a shell that had inherited none of the session's
variables -- no `XDG_RUNTIME_DIR`, no `WAYLAND_DISPLAY`, no `DISPLAY` -- while
`/run/user/1000/wayland-1` and `/tmp/.X11-unix/X0` were both sitting there. The
old logic read `$WAYLAND_DISPLAY`, found nothing, chose x11, and Chromium died
on `Missing X server or $DISPLAY` with both working sockets untouched.
"""

from __future__ import annotations

import os
import socket
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import kcl_fetch
from kcl_fetch_lib import display as display_mod


def make_socket(path: Path) -> Path:
    """A genuine AF_UNIX socket, bound and left on disk."""
    path.parent.mkdir(parents=True, exist_ok=True)
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(str(path))
    # The listener is closed; the inode stays, exactly as a compositor's
    # socket looks to anyone probing the directory.
    sock.close()
    return path


class DisplayCase(unittest.TestCase):
    """A fake runtime dir and a fake /tmp/.X11-unix, with nothing inherited."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        root = Path(self._tmp.name)
        self.runtime = root / "run" / "user" / str(os.getuid())
        self.runtime.mkdir(parents=True)
        self.x11 = root / "X11-unix"
        self.x11.mkdir()
        # `{uid}` is left in the template so `runtime_dir` formats it itself --
        # the same code path the real "/run/user/{uid}" fallback takes.
        template = str(root / "run" / "user" / "{uid}")
        patches = (
            mock.patch.object(display_mod, "RUNTIME_DIR_TEMPLATE", template),
            mock.patch.object(display_mod, "X11_SOCKET_DIR", self.x11),
        )
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        self.addCleanup(self._tmp.cleanup)

    def resolve(self, explicit=None, **environ):
        return display_mod.resolve(explicit, environ)


class TestTheReproducedBug(DisplayCase):
    def test_a_wayland_socket_is_used_when_no_variable_names_it(self):
        """The exact failure: sockets present, all three variables absent."""
        make_socket(self.runtime / "wayland-1")
        (self.runtime / "wayland-1.lock").write_text("")
        make_socket(self.x11 / "X0")

        chosen = self.resolve()

        self.assertEqual(chosen.platform, "wayland")
        self.assertEqual(chosen.env["WAYLAND_DISPLAY"], "wayland-1")
        # Without this Chromium cannot find the socket we just located.
        self.assertEqual(chosen.env["XDG_RUNTIME_DIR"], str(self.runtime))
        self.assertEqual(chosen.ozone_args(), ("--ozone-platform=wayland",))

    def test_the_old_logic_would_have_chosen_x11_here(self):
        """Same directory state, and x11 is the answer only if Wayland is gone."""
        make_socket(self.x11 / "X0")
        self.assertEqual(self.resolve().platform, "x11")
        make_socket(self.runtime / "wayland-1")
        self.assertEqual(self.resolve().platform, "wayland")


class TestSocketDiscrimination(DisplayCase):
    def test_a_lock_file_beside_the_socket_is_not_a_socket(self):
        make_socket(self.runtime / "wayland-1")
        (self.runtime / "wayland-1.lock").write_text("")
        self.assertEqual(display_mod._wayland_sockets(self.runtime), ["wayland-1"])

    def test_a_plain_file_with_a_socket_name_is_rejected(self):
        """Same name, different mode: only `S_ISSOCK` tells them apart."""
        (self.runtime / "wayland-0").write_text("not a socket")
        make_socket(self.runtime / "wayland-1")

        self.assertEqual(display_mod._wayland_sockets(self.runtime), ["wayland-1"])
        self.assertEqual(self.resolve().env["WAYLAND_DISPLAY"], "wayland-1")

    def test_a_directory_named_like_a_socket_is_rejected(self):
        (self.runtime / "wayland-0").mkdir()
        self.assertEqual(display_mod._wayland_sockets(self.runtime), [])

    def test_x_neighbours_that_are_not_displays_are_ignored(self):
        """`/tmp/.X11-unix` really does hold an `X0_` next to `X0`."""
        make_socket(self.x11 / "X0")
        make_socket(self.x11 / "X0_")
        (self.x11 / "X1").write_text("plain file")
        self.assertEqual([n for n, _ in display_mod._x_displays(self.x11)], [0])


class TestTheLadder(DisplayCase):
    def test_a_named_wayland_display_with_a_socket_is_believed(self):
        make_socket(self.runtime / "wayland-3")
        chosen = self.resolve(WAYLAND_DISPLAY="wayland-3")
        self.assertEqual(chosen.platform, "wayland")
        self.assertEqual(chosen.env["WAYLAND_DISPLAY"], "wayland-3")

    def test_a_named_wayland_display_without_a_socket_is_not_trusted(self):
        """The variable is a hint. It survives only if the socket backs it."""
        make_socket(self.runtime / "wayland-1")
        chosen = self.resolve(WAYLAND_DISPLAY="wayland-9")
        self.assertEqual(chosen.platform, "wayland")
        self.assertEqual(chosen.env["WAYLAND_DISPLAY"], "wayland-1")

    def test_a_stale_wayland_variable_falls_all_the_way_through_to_x11(self):
        make_socket(self.x11 / "X0")
        chosen = self.resolve(WAYLAND_DISPLAY="wayland-9")
        self.assertEqual(chosen.platform, "x11")
        self.assertEqual(chosen.env["DISPLAY"], ":0")

    def test_an_absolute_wayland_display_is_taken_as_a_path(self):
        socket_path = make_socket(self.runtime / "elsewhere" / "wayland-7")
        chosen = self.resolve(WAYLAND_DISPLAY=str(socket_path))
        self.assertEqual(chosen.platform, "wayland")
        self.assertEqual(chosen.env["WAYLAND_DISPLAY"], str(socket_path))

    def test_an_x_socket_supplies_the_display_number(self):
        make_socket(self.x11 / "X0")
        chosen = self.resolve()
        self.assertEqual(chosen.platform, "x11")
        self.assertEqual(chosen.env["DISPLAY"], ":0")

    def test_an_existing_display_variable_is_used_as_given(self):
        chosen = self.resolve(DISPLAY=":12")
        self.assertEqual(chosen.platform, "x11")
        self.assertEqual(chosen.env["DISPLAY"], ":12")

    def test_wayland_outranks_a_set_display_variable(self):
        make_socket(self.runtime / "wayland-1")
        self.assertEqual(self.resolve(DISPLAY=":0").platform, "wayland")

    def test_an_explicit_runtime_dir_wins_over_the_fallback(self):
        other = Path(self._tmp.name) / "other-runtime"
        make_socket(other / "wayland-4")
        make_socket(self.runtime / "wayland-1")
        chosen = self.resolve(XDG_RUNTIME_DIR=str(other))
        self.assertEqual(chosen.env["WAYLAND_DISPLAY"], "wayland-4")
        self.assertEqual(chosen.env["XDG_RUNTIME_DIR"], str(other))

    def test_an_empty_runtime_dir_variable_falls_back(self):
        make_socket(self.runtime / "wayland-1")
        chosen = self.resolve(XDG_RUNTIME_DIR="")
        self.assertEqual(chosen.env["XDG_RUNTIME_DIR"], str(self.runtime))


class TestDeterminism(DisplayCase):
    def test_the_lowest_numbered_wayland_socket_wins(self):
        for name in ("wayland-10", "wayland-2", "wayland-0"):
            make_socket(self.runtime / name)
        chosen = self.resolve()
        self.assertEqual(chosen.env["WAYLAND_DISPLAY"], "wayland-0")

    def test_the_rejected_sockets_are_named_in_the_detail(self):
        make_socket(self.runtime / "wayland-1")
        make_socket(self.runtime / "wayland-0")
        detail = self.resolve().detail
        self.assertIn("wayland-0", detail)
        self.assertIn("ignoring wayland-1", detail)

    def test_the_lowest_numbered_x_display_wins(self):
        make_socket(self.x11 / "X7")
        make_socket(self.x11 / "X1")
        chosen = self.resolve()
        self.assertEqual(chosen.env["DISPLAY"], ":1")
        self.assertIn(":7", chosen.detail)


class TestExplicitPlatform(DisplayCase):
    def test_x11_can_be_forced_over_a_detected_wayland(self):
        make_socket(self.runtime / "wayland-1")
        chosen = self.resolve("x11")
        self.assertEqual(chosen.ozone_args(), ("--ozone-platform=x11",))
        self.assertNotIn("WAYLAND_DISPLAY", chosen.env)

    def test_wayland_can_be_forced_over_a_detected_x11(self):
        make_socket(self.x11 / "X0")
        chosen = self.resolve("wayland")
        self.assertEqual(chosen.ozone_args(), ("--ozone-platform=wayland",))
        self.assertNotIn("DISPLAY", chosen.env)

    def test_a_forced_platform_survives_finding_nothing_at_all(self):
        """The user may know something the probe cannot -- no refusal here."""
        chosen = self.resolve("wayland")
        self.assertEqual(chosen.platform, "wayland")
        self.assertEqual(chosen.env, {})

    def test_a_forced_platform_still_collects_the_variables_it_agrees_with(self):
        make_socket(self.runtime / "wayland-1")
        chosen = self.resolve("wayland")
        self.assertEqual(chosen.env["WAYLAND_DISPLAY"], "wayland-1")
        self.assertEqual(chosen.env["XDG_RUNTIME_DIR"], str(self.runtime))

    def test_forcing_x11_on_a_wayland_desktop_still_finds_xwayland(self):
        """Both sockets are up. Forcing x11 must export the X one, not nothing."""
        make_socket(self.runtime / "wayland-1")
        make_socket(self.x11 / "X0")
        chosen = self.resolve("x11")
        self.assertEqual(chosen.platform, "x11")
        self.assertEqual(chosen.env, {"DISPLAY": ":0"})

    def test_forcing_wayland_from_an_x_only_shell_exports_nothing_it_invented(self):
        make_socket(self.x11 / "X0")
        self.assertEqual(self.resolve("wayland").env, {})

    def test_an_unknown_platform_is_passed_through_unprobed(self):
        make_socket(self.runtime / "wayland-1")
        chosen = self.resolve("headless")
        self.assertEqual(chosen.ozone_args(), ("--ozone-platform=headless",))
        self.assertEqual(chosen.env, {})


class TestNoDisplayAtAll(DisplayCase):
    def test_an_empty_session_refuses(self):
        with self.assertRaises(display_mod.NoDisplay) as caught:
            self.resolve()
        message = str(caught.exception)
        self.assertIn("no display found", message)
        self.assertIn("--ozone-platform", message)

    def test_the_advice_names_both_directories_it_looked_in(self):
        with self.assertRaises(display_mod.NoDisplay) as caught:
            self.resolve()
        self.assertIn(str(self.runtime), str(caught.exception))
        self.assertIn(str(self.x11), str(caught.exception))

    def test_the_cli_exits_nonzero_with_one_line_and_no_traceback(self):
        home = Path(self._tmp.name) / "home"
        home.mkdir()
        with mock.patch.dict(os.environ, {"HOME": str(home)}, clear=True):
            with mock.patch("sys.stderr", new_callable=_Capture) as err:
                code = kcl_fetch.main(["login"])

        self.assertEqual(code, 2)
        printed = err.text.strip()
        self.assertNotIn("Traceback", printed)
        self.assertEqual(len(printed.splitlines()), 1)
        self.assertTrue(printed.startswith("kcl-fetch: no display found"), printed)

    def test_nothing_is_launched_when_there_is_no_display(self):
        """`get` must refuse before LibKey, Crossref or a gate slot."""
        home = Path(self._tmp.name) / "home-get"
        home.mkdir()
        with mock.patch.object(kcl_fetch.libkey, "precheck") as precheck:
            with mock.patch.dict(os.environ, {"HOME": str(home)}, clear=True):
                with mock.patch("sys.stderr", new_callable=_Capture):
                    code = kcl_fetch.main(["get", "10.1000/x"])
        self.assertEqual(code, 2)
        precheck.assert_not_called()


class _Capture:
    """Minimal stderr stand-in -- `mock.patch` needs something writable."""

    def __init__(self) -> None:
        self.text = ""

    def write(self, chunk: str) -> int:
        self.text += chunk
        return len(chunk)

    def flush(self) -> None:
        pass


if __name__ == "__main__":
    unittest.main()
