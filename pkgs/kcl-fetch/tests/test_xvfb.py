"""The virtual display: invisible without being headless.

`get` used to paint a Chromium window on whatever screen the user was looking
at, once per fetch. The fix is not `headless=True` -- headless is the single
strongest bot signal a publisher SP looks for, and this session carries an
institutional identity -- but a private X server the same headed browser paints
on instead.

What is guarded here is the lifecycle, because the failure modes are all quiet
ones: a server that outlives the command, a launch that silently lands on the
real display, or a missing Xvfb that degrades into the window we were asked to
suppress.
"""

from __future__ import annotations

import argparse
import atexit
import contextlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import kcl_fetch
from kcl_fetch_lib import display as display_mod
from kcl_fetch_lib import driver as driver_mod
from kcl_fetch_lib import xvfb
from test_profile_lock import fake_playwright


class FakeXvfb:
    """Stands in for `subprocess.Popen`, and for the server it would start.

    Called as the spawn function, returned as the process. `-displayfd` is
    honoured for real -- the number really is written down a real pipe -- so
    the handshake under test is the one the X server performs.
    """

    def __init__(self, number: int = 99, *, announce: bool = True,
                 log: bytes = b"", hold: bool = False):
        self.number = number
        self.announce = announce
        self.log = log
        self.hold = hold
        self.argv: list[str] = []
        self.kwargs: dict = {}
        self.terminated = 0
        self.killed = 0
        self.waits: list = []
        self._held_fd: int | None = None

    def __call__(self, argv, **kwargs):
        self.argv = list(argv)
        self.kwargs = kwargs
        fd = int(self.argv[self.argv.index("-displayfd") + 1])
        if self.log:
            kwargs["stderr"].write(self.log)
            kwargs["stderr"].flush()
        if self.announce:
            os.write(fd, f"{self.number}\n".encode())
        if self.hold:
            # Keeps the write end open, so the reader waits instead of seeing
            # EOF -- an Xvfb that started and then hung.
            self._held_fd = os.dup(fd)
        return self

    def release(self) -> None:
        if self._held_fd is not None:
            os.close(self._held_fd)
            self._held_fd = None

    # -- the process half --------------------------------------------------

    def terminate(self) -> None:
        self.terminated += 1

    def kill(self) -> None:
        self.killed += 1

    def wait(self, timeout=None):
        self.waits.append(timeout)
        return 0


class TestResolvingTheBinary(unittest.TestCase):
    def test_the_baked_in_path_is_used_when_it_exists(self):
        with tempfile.NamedTemporaryFile() as fake:
            found = xvfb.resolve_binary(
                environ={xvfb.XVFB_ENV: fake.name}, which=lambda _n: None
            )
        self.assertEqual(found, fake.name)

    def test_a_stale_baked_in_path_falls_through_to_the_search(self):
        found = xvfb.resolve_binary(
            environ={xvfb.XVFB_ENV: "/nonexistent/Xvfb"},
            which=lambda name: f"/usr/bin/{name}",
        )
        self.assertEqual(found, "/usr/bin/Xvfb")

    def test_no_xvfb_anywhere_is_one_clear_line(self):
        with self.assertRaises(xvfb.XvfbUnavailable) as caught:
            xvfb.resolve_binary(environ={}, which=lambda _n: None)
        message = str(caught.exception)
        self.assertEqual(len(message.splitlines()), 1)
        self.assertIn("Xvfb", message)
        self.assertIn("--show", message)

    def test_it_never_offers_headless_as_the_way_out(self):
        """Falling back to headless would trade the window for the bot signal."""
        with self.assertRaises(xvfb.XvfbUnavailable) as caught:
            xvfb.resolve_binary(environ={}, which=lambda _n: None)
        self.assertNotIn("headless", str(caught.exception).lower())


class TestStarting(unittest.TestCase):
    def display(self, fake: FakeXvfb, **kwargs):
        server = xvfb.VirtualDisplay(binary="/bin/Xvfb", spawn=fake, **kwargs)
        self.addCleanup(server.stop)
        self.addCleanup(fake.release)
        return server, server.start()

    def test_the_display_number_comes_from_the_server(self):
        """Never chosen by us: picking `:N` ourselves races every X client."""
        fake = FakeXvfb(number=77)
        _, screen = self.display(fake)
        self.assertEqual(screen.platform, "x11")
        self.assertEqual(screen.env["DISPLAY"], ":77")
        self.assertIn("-displayfd", fake.argv)

    def test_the_browser_is_told_x11_and_the_wayland_socket_is_withdrawn(self):
        _, screen = self.display(FakeXvfb())
        self.assertEqual(screen.ozone_args(), ("--ozone-platform=x11",))
        self.assertIn(display_mod.WAYLAND_VAR, screen.unset)

    def test_the_server_is_desktop_sized_and_refuses_tcp(self):
        fake = FakeXvfb()
        self.display(fake)
        self.assertIn(xvfb.SCREEN, fake.argv)
        self.assertIn("-nolisten", fake.argv)
        self.assertIn("tcp", fake.argv)

    def test_a_server_that_dies_without_a_display_says_why(self):
        fake = FakeXvfb(announce=False, log=b"(EE) Fatal server error:\ncannot open\n")
        server = xvfb.VirtualDisplay(binary="/bin/Xvfb", spawn=fake)
        with self.assertRaises(xvfb.XvfbUnavailable) as caught:
            server.start()
        self.assertIn("without opening a display", str(caught.exception))
        self.assertIn("cannot open", str(caught.exception))

    def test_a_server_that_never_answers_times_out_rather_than_hanging(self):
        fake = FakeXvfb(announce=False, hold=True)
        self.addCleanup(fake.release)
        server = xvfb.VirtualDisplay(binary="/bin/Xvfb", spawn=fake, timeout=0.05)
        with self.assertRaises(xvfb.XvfbUnavailable) as caught:
            server.start()
        self.assertIn("did not report a display", str(caught.exception))
        self.assertEqual(fake.terminated, 1)

    def test_a_binary_that_will_not_execute_is_not_a_traceback(self):
        def explode(*_a, **_k):
            raise OSError(2, "No such file or directory")

        server = xvfb.VirtualDisplay(binary="/bin/Xvfb", spawn=explode)
        with self.assertRaises(xvfb.XvfbUnavailable) as caught:
            server.start()
        self.assertIn("could not start", str(caught.exception))


class TestStopping(unittest.TestCase):
    """A leaked X server survives the command that started it. It must not."""

    def server(self, fake: FakeXvfb) -> xvfb.VirtualDisplay:
        return xvfb.VirtualDisplay(binary="/bin/Xvfb", spawn=fake)

    def test_the_context_manager_reaps_the_server(self):
        fake = FakeXvfb()
        with self.server(fake) as server:
            self.assertEqual(server.display.env["DISPLAY"], ":99")
        self.assertEqual(fake.terminated, 1)

    def test_an_exception_inside_the_block_still_reaps_the_server(self):
        fake = FakeXvfb()
        with self.assertRaises(ZeroDivisionError):
            with self.server(fake):
                raise ZeroDivisionError("the fetch blew up")
        self.assertEqual(fake.terminated, 1)

    def test_a_keyboard_interrupt_still_reaps_the_server(self):
        """SIGINT arrives as an exception, and unwinds the block like any other."""
        fake = FakeXvfb()
        with self.assertRaises(KeyboardInterrupt):
            with self.server(fake):
                raise KeyboardInterrupt
        self.assertEqual(fake.terminated, 1)

    def test_a_server_that_ignores_terminate_is_killed(self):
        fake = FakeXvfb()

        def refuse(timeout=None):
            raise TimeoutError("still running")

        fake.wait = refuse
        with self.server(fake):
            pass
        self.assertEqual(fake.killed, 1)

    def test_stopping_twice_is_harmless(self):
        fake = FakeXvfb()
        server = self.server(fake)
        server.start()
        server.stop()
        server.stop()
        self.assertEqual(fake.terminated, 1)

    def test_the_atexit_handler_is_armed_and_then_withdrawn(self):
        """Registered for the exits that never unwind, gone once it is moot."""
        fake = FakeXvfb()
        server = self.server(fake)
        with mock.patch.object(atexit, "register") as register:
            with mock.patch.object(atexit, "unregister") as unregister:
                server.start()
                register.assert_called_once_with(server.stop)
                unregister.assert_not_called()
                server.stop()
                unregister.assert_called_once_with(server.stop)

    def test_the_fetch_stack_reaps_it_even_when_the_fetch_raises(self):
        """`cmd_get`'s own unwinding, not just the context manager's."""
        fake = FakeXvfb()
        server = self.server(fake)
        with self.assertRaises(RuntimeError):
            with contextlib.ExitStack() as stack:
                stack.enter_context(server)
                raise RuntimeError("crossref exploded")
        self.assertEqual(fake.terminated, 1)


class TestTheBrowserEnvironment(unittest.TestCase):
    """Setting `DISPLAY` is not enough on a Wayland desktop."""

    def test_the_inherited_wayland_socket_is_dropped(self):
        screen = display_mod.virtual_x11(41, "test")
        browser = driver_mod.Browser(
            profile_dir=Path(tempfile.mkdtemp()),
            chromium="/nonexistent/chromium",
            downloads_dir=Path(tempfile.mkdtemp()),
            env=screen.env,
            env_unset=screen.unset,
        )
        with mock.patch.dict(
            os.environ,
            {"WAYLAND_DISPLAY": "wayland-1", "PATH": "/usr/bin"},
            clear=True,
        ):
            env = browser.browser_env()
        self.assertEqual(env["DISPLAY"], ":41")
        self.assertNotIn("WAYLAND_DISPLAY", env)
        self.assertEqual(env["PATH"], "/usr/bin")


class TestTheGetCommandsScreen(unittest.TestCase):
    def args(self, **kwargs):
        return argparse.Namespace(
            **{"ozone_platform": None, "verbose": False, "show": False, **kwargs}
        )

    def test_get_defaults_to_a_virtual_display_and_never_probes_the_session(self):
        fake = FakeXvfb(number=88)
        real = xvfb.VirtualDisplay
        with mock.patch.object(display_mod, "resolve") as resolve:
            with mock.patch.object(
                xvfb, "VirtualDisplay",
                lambda **_k: real(binary="/bin/Xvfb", spawn=fake),
            ):
                with contextlib.ExitStack() as stack:
                    screen = kcl_fetch._get_screen(self.args(), stack)
                    self.assertEqual(screen.env["DISPLAY"], ":88")
        resolve.assert_not_called()
        # Leaving the stack is what tears the server down.
        self.assertEqual(fake.terminated, 1)

    def test_show_puts_the_window_back_on_the_users_own_screen(self):
        chosen = display_mod.Display("wayland", {"WAYLAND_DISPLAY": "wayland-1"}, "d")
        with mock.patch.object(display_mod, "resolve", return_value=chosen):
            with mock.patch.object(xvfb, "VirtualDisplay") as virtual:
                with contextlib.ExitStack() as stack:
                    screen = kcl_fetch._get_screen(self.args(show=True), stack)
        self.assertIs(screen, chosen)
        virtual.assert_not_called()

    def test_an_ozone_platform_without_show_is_refused_rather_than_ignored(self):
        with contextlib.ExitStack() as stack:
            with self.assertRaises(SystemExit) as caught:
                kcl_fetch._get_screen(self.args(ozone_platform="x11"), stack)
        self.assertIn("--show", str(caught.exception))

    def test_an_ozone_platform_with_show_is_honoured(self):
        with mock.patch.object(display_mod, "resolve") as resolve:
            with contextlib.ExitStack() as stack:
                kcl_fetch._get_screen(
                    self.args(show=True, ozone_platform="x11"), stack
                )
        resolve.assert_called_once_with("x11")


class TestTheFlag(unittest.TestCase):
    def setUp(self) -> None:
        self.parser = kcl_fetch.build_parser()

    def test_get_is_invisible_unless_asked(self):
        self.assertFalse(self.parser.parse_args(["get", "10.1000/x"]).show)

    def test_show_and_visible_are_the_same_flag(self):
        self.assertTrue(self.parser.parse_args(["get", "10.1000/x", "--show"]).show)
        self.assertTrue(self.parser.parse_args(["get", "10.1000/x", "--visible"]).show)

    def test_login_has_no_such_flag_because_it_is_always_visible(self):
        """MFA needs a human looking at the window; there is nothing to toggle."""
        self.assertFalse(hasattr(self.parser.parse_args(["login"]), "show"))


class TestMissingXvfbAtRuntime(unittest.TestCase):
    def test_the_cli_stops_with_one_line_and_spends_nothing(self):
        with mock.patch.object(kcl_fetch.libkey, "precheck") as precheck:
            with mock.patch.object(
                xvfb, "resolve_binary",
                side_effect=xvfb.XvfbUnavailable("no Xvfb on PATH"),
            ):
                with mock.patch("sys.stderr", new_callable=_Capture) as err:
                    code = kcl_fetch.main(["get", "10.1000/x"])
        self.assertEqual(code, 2)
        precheck.assert_not_called()
        printed = err.text.strip()
        self.assertNotIn("Traceback", printed)
        self.assertEqual(printed, "kcl-fetch: no Xvfb on PATH")

    def test_show_does_not_need_xvfb_at_all(self):
        chosen = display_mod.Display("wayland", {}, "d")
        with mock.patch.object(xvfb, "resolve_binary") as resolve:
            with mock.patch.object(display_mod, "resolve", return_value=chosen):
                with contextlib.ExitStack() as stack:
                    kcl_fetch._get_screen(
                        argparse.Namespace(
                            ozone_platform=None, verbose=False, show=True
                        ),
                        stack,
                    )
        resolve.assert_not_called()


class _Capture:
    def __init__(self) -> None:
        self.text = ""

    def write(self, chunk: str) -> int:
        self.text += chunk
        return len(chunk)

    def flush(self) -> None:
        pass


if __name__ == "__main__":
    unittest.main()
