"""Chromium's singleton lock: diagnosed, described, never deleted.

A killed launch leaves `SingletonLock -> <host>-<pid>` behind. Chromium usually
reclaims it, but when it does not the failure arrives as a Playwright
`TargetClosedError` that says nothing about a lock. The point of this code is
to turn that into a sentence naming the three files -- and then to stop, because
the profile is the institutional session and re-running MFA is the cost of
guessing wrong.
"""

from __future__ import annotations

import contextlib
import os
import socket
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock

from kcl_fetch_lib import driver as driver_mod


@contextlib.contextmanager
def fake_playwright(start_result):
    """Stand in for the `playwright` package, installed or not.

    `driver` imports it lazily inside `__enter__`, so a module object in
    `sys.modules` is enough -- and nothing here is about Playwright's own
    behaviour, only about what we hand it and what we do when it throws.
    """
    package = types.ModuleType("playwright")
    sync_api = types.ModuleType("playwright.sync_api")
    sync_api.sync_playwright = mock.MagicMock()
    sync_api.sync_playwright.return_value.start.return_value = start_result
    package.sync_api = sync_api
    with mock.patch.dict(
        sys.modules, {"playwright": package, "playwright.sync_api": sync_api}
    ):
        yield sync_api.sync_playwright


class ProfileCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.profile = Path(self._tmp.name) / "profile"
        self.profile.mkdir()
        self.addCleanup(self._tmp.cleanup)

    def lock(self, target: str) -> None:
        os.symlink(target, self.profile / "SingletonLock")

    def dead_pid(self) -> int:
        """A pid that has certainly exited: a child we reaped ourselves."""
        pid = os.fork()
        if pid == 0:  # pragma: no cover -- the child never returns
            os._exit(0)
        os.waitpid(pid, 0)
        return pid


class TestStaleDetection(ProfileCase):
    def test_no_lock_is_not_a_diagnosis(self):
        self.assertIsNone(driver_mod.stale_singleton_advice(self.profile))

    def test_a_missing_profile_is_not_a_diagnosis(self):
        self.assertIsNone(driver_mod.stale_singleton_advice(self.profile / "absent"))

    def test_a_live_pid_is_left_alone(self):
        """Another window really is open -- that is not a stale lock."""
        self.lock(f"{socket.gethostname()}-{os.getpid()}")
        self.assertIsNone(driver_mod.stale_singleton_advice(self.profile))

    def test_a_dead_pid_on_this_host_is_reported(self):
        pid = self.dead_pid()
        self.lock(f"{socket.gethostname()}-{pid}")
        advice = driver_mod.stale_singleton_advice(self.profile)
        self.assertIsNotNone(advice)
        self.assertIn(str(pid), advice)

    def test_a_lock_from_another_host_says_nothing_about_this_one(self):
        self.lock(f"not-{socket.gethostname()}-{self.dead_pid()}")
        self.assertIsNone(driver_mod.stale_singleton_advice(self.profile))

    def test_an_unparseable_target_is_not_guessed_at(self):
        self.lock("something-else")
        self.assertIsNone(driver_mod.stale_singleton_advice(self.profile))

    def test_the_advice_names_every_entry_to_remove(self):
        self.lock(f"{socket.gethostname()}-{self.dead_pid()}")
        advice = driver_mod.stale_singleton_advice(self.profile)
        for name in driver_mod.SINGLETON_ENTRIES:
            self.assertIn(str(self.profile / name), advice)

    def test_the_advice_deletes_nothing(self):
        self.lock(f"{socket.gethostname()}-{self.dead_pid()}")
        driver_mod.stale_singleton_advice(self.profile)
        self.assertTrue((self.profile / "SingletonLock").is_symlink())


class TestTheBeforePicture(ProfileCase):
    """A dying Chromium writes its own lock; that one is not to blame."""

    def test_a_lock_written_during_the_attempt_is_not_blamed(self):
        target = f"{socket.gethostname()}-{self.dead_pid()}"
        self.lock(target)
        self.assertIsNone(
            driver_mod.stale_singleton_advice(self.profile, before=None)
        )

    def test_a_lock_that_changed_during_the_attempt_is_not_blamed(self):
        self.lock(f"{socket.gethostname()}-{self.dead_pid()}")
        self.assertIsNone(
            driver_mod.stale_singleton_advice(self.profile, before="linglong-1")
        )

    def test_the_lock_that_was_already_there_is_blamed(self):
        target = f"{socket.gethostname()}-{self.dead_pid()}"
        self.lock(target)
        advice = driver_mod.stale_singleton_advice(self.profile, before=target)
        self.assertIsNotNone(advice)

    def test_singleton_target_reads_the_symlink(self):
        self.assertIsNone(driver_mod.singleton_target(self.profile))
        self.lock("linglong-42")
        self.assertEqual(driver_mod.singleton_target(self.profile), "linglong-42")


class TestLaunchFailure(ProfileCase):
    """The launch exception is reshaped only when a stale lock explains it."""

    def _launch(self):
        browser = driver_mod.Browser(
            profile_dir=self.profile,
            chromium="/nonexistent/chromium",
            downloads_dir=Path(self._tmp.name) / "downloads",
        )
        fake = mock.MagicMock()
        fake.chromium.launch_persistent_context.side_effect = RuntimeError(
            "Target page, context or browser has been closed"
        )
        with fake_playwright(fake):
            with self.assertRaises(Exception) as caught:
                browser.__enter__()
        return caught.exception, fake

    def test_a_stale_lock_turns_the_failure_into_advice(self):
        self.lock(f"{socket.gethostname()}-{self.dead_pid()}")
        exc, _ = self._launch()
        self.assertIsInstance(exc, driver_mod.StaleProfileLock)
        self.assertIn("SingletonLock", str(exc))

    def test_an_unexplained_failure_is_re_raised_as_it_came(self):
        exc, _ = self._launch()
        self.assertIsInstance(exc, RuntimeError)
        self.assertNotIsInstance(exc, driver_mod.StaleProfileLock)

    def test_a_lock_appearing_only_during_the_attempt_is_not_blamed(self):
        """The observed regression: a no-display Chromium leaves its own lock."""
        pid = self.dead_pid()
        browser = driver_mod.Browser(
            profile_dir=self.profile,
            chromium="/nonexistent/chromium",
            downloads_dir=Path(self._tmp.name) / "downloads",
        )
        fake = mock.MagicMock()

        def die(*_args, **_kwargs):
            os.symlink(f"{socket.gethostname()}-{pid}",
                       self.profile / "SingletonLock")
            raise RuntimeError("Target page, context or browser has been closed")

        fake.chromium.launch_persistent_context.side_effect = die
        with fake_playwright(fake):
            with self.assertRaises(RuntimeError) as caught:
                browser.__enter__()
        self.assertNotIsInstance(caught.exception, driver_mod.StaleProfileLock)

    def test_the_playwright_driver_is_stopped_on_a_failed_launch(self):
        _, fake = self._launch()
        fake.stop.assert_called_once()


class TestBrowserEnvironment(ProfileCase):
    """The display variables have to reach the browser, not just this process."""

    def test_the_probed_variables_are_layered_over_the_parent_environment(self):
        browser = driver_mod.Browser(
            profile_dir=self.profile,
            chromium="/nonexistent/chromium",
            downloads_dir=Path(self._tmp.name) / "downloads",
            extra_args=("--ozone-platform=wayland",),
            env={"WAYLAND_DISPLAY": "wayland-1", "XDG_RUNTIME_DIR": "/run/user/1000"},
        )
        fake = mock.MagicMock()
        with fake_playwright(fake):
            with mock.patch.dict(os.environ, {"PATH": "/usr/bin"}, clear=True):
                browser.__enter__()

        kwargs = fake.chromium.launch_persistent_context.call_args.kwargs
        self.assertEqual(kwargs["env"]["WAYLAND_DISPLAY"], "wayland-1")
        self.assertEqual(kwargs["env"]["XDG_RUNTIME_DIR"], "/run/user/1000")
        # Playwright's `env` replaces the browser's whole environment, so the
        # inherited entries must survive the merge.
        self.assertEqual(kwargs["env"]["PATH"], "/usr/bin")
        self.assertIn("--ozone-platform=wayland", kwargs["args"])

    def test_our_own_environment_is_not_modified(self):
        browser = driver_mod.Browser(
            profile_dir=self.profile,
            chromium="/nonexistent/chromium",
            downloads_dir=Path(self._tmp.name) / "downloads",
            env={"WAYLAND_DISPLAY": "wayland-1"},
        )
        fake = mock.MagicMock()
        with fake_playwright(fake):
            with mock.patch.dict(os.environ, {"PATH": "/usr/bin"}, clear=True):
                browser.__enter__()
                self.assertNotIn("WAYLAND_DISPLAY", os.environ)


if __name__ == "__main__":
    unittest.main()
