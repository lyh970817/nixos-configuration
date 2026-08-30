"""Sending the sign-in to the machine the human is sitting at.

Nothing here shells out: the runner is injected, so what is under test is the
argv that would have been executed, the status that comes back from it, and the
note printed when the window would open on the wrong screen.
"""

from __future__ import annotations

import argparse
import unittest
from unittest import mock

import kcl_fetch
from kcl_fetch_lib import remote


def _argv(host="peerbox", **flags):
    return remote.login_argv(host, **flags)


class TestLoginArgv(unittest.TestCase):
    def test_the_remote_command_is_the_same_login(self):
        self.assertEqual(
            _argv(),
            ["ssh", "peerbox", "env", "KCL_FETCH_DISPATCHED=1", "kcl-fetch", "login"],
        )

    def test_the_dispatch_marker_travels_as_an_environment_variable(self):
        """A peer on an older build must ignore it, not die on an unknown flag."""
        self.assertIn(f"{remote.DISPATCH_ENV}=1", _argv())
        self.assertNotIn("--no-ssh-hint", _argv())

    def test_the_timeout_is_forwarded_without_a_float_tail(self):
        self.assertEqual(_argv(timeout=900.0)[-2:], ["--timeout", "900"])
        self.assertEqual(_argv(timeout=2.5)[-2:], ["--timeout", "2.5"])

    def test_no_timeout_means_no_flag(self):
        self.assertNotIn("--timeout", _argv())

    def test_the_ozone_platform_is_forwarded(self):
        self.assertEqual(_argv(ozone_platform="x11")[-2:], ["--ozone-platform", "x11"])
        self.assertNotIn("--ozone-platform", _argv(ozone_platform=None))

    def test_verbose_is_forwarded_only_when_set(self):
        self.assertIn("--verbose", _argv(verbose=True))
        self.assertNotIn("--verbose", _argv(verbose=False))

    def test_every_flag_at_once_keeps_the_login_first(self):
        self.assertEqual(
            _argv(timeout=30, ozone_platform="wayland", verbose=True),
            [
                "ssh",
                "peerbox",
                "env",
                "KCL_FETCH_DISPATCHED=1",
                "kcl-fetch",
                "login",
                "--timeout",
                "30",
                "--ozone-platform",
                "wayland",
                "--verbose",
            ],
        )

    def test_a_tty_is_requested_only_when_asked_for(self):
        self.assertEqual(_argv(tty=True)[:3], ["ssh", "-t", "peerbox"])
        self.assertNotIn("-t", _argv(tty=False))

    def test_remote_words_are_quoted_for_the_far_side_shell(self):
        """ssh hands the command to a shell, which parses it a second time."""
        self.assertIn("'wayland or else'", _argv(ozone_platform="wayland or else"))


class TestResolveHost(unittest.TestCase):
    def test_an_explicit_host_is_used_as_given(self):
        self.assertEqual(remote.resolve_host("dynabook", {}), "dynabook")

    def test_the_bare_flag_means_the_configured_peer(self):
        env = {remote.PEER_HOST_ENV: "dynabook"}
        self.assertEqual(remote.resolve_host(remote.PEER, env), "dynabook")

    def test_the_bare_flag_without_a_peer_is_one_clear_line(self):
        with self.assertRaises(remote.RemoteError) as caught:
            remote.resolve_host(remote.PEER, {})
        self.assertIn("--on HOST", str(caught.exception))

    def test_a_host_that_would_read_as_an_ssh_option_is_refused(self):
        with self.assertRaises(remote.RemoteError):
            remote.resolve_host("-oProxyCommand=touch /tmp/pwned", {})

    def test_an_empty_host_is_refused(self):
        with self.assertRaises(remote.RemoteError):
            remote.resolve_host("   ", {})


class TestDispatchStatus(unittest.TestCase):
    def test_the_remote_status_is_what_comes_back(self):
        for status in (0, 1, 2, 5):
            with self.subTest(status=status):
                runner = mock.Mock(return_value=status)
                self.assertEqual(
                    remote.dispatch_login("peerbox", runner=runner), status
                )
        runner.assert_called_with(_argv())

    def test_a_missing_ssh_is_a_remote_error_not_a_traceback(self):
        runner = mock.Mock(side_effect=FileNotFoundError(2, "No such file"))
        with self.assertRaises(remote.RemoteError) as caught:
            remote.dispatch_login("peerbox", runner=runner)
        self.assertIn("ssh", str(caught.exception))

    def test_any_other_os_error_is_also_one_line(self):
        runner = mock.Mock(side_effect=PermissionError(13, "Denied"))
        with self.assertRaises(remote.RemoteError):
            remote.dispatch_login("peerbox", runner=runner)


class TestSshHint(unittest.TestCase):
    def test_silent_when_there_is_no_ssh_session(self):
        self.assertIsNone(remote.ssh_hint({}, hostname="linglong"))

    def test_it_names_the_client_and_this_hosts_screen(self):
        note = remote.ssh_hint(
            {"SSH_CONNECTION": "100.64.0.2 51234 100.64.0.1 22"},
            hostname="linglong",
        )
        self.assertIn("100.64.0.2", note)
        self.assertIn("linglong", note)
        self.assertIn("--on HOST", note)

    def test_a_configured_peer_is_named_as_the_argument_to_try(self):
        note = remote.ssh_hint(
            {
                "SSH_CONNECTION": "100.64.0.2 51234 100.64.0.1 22",
                remote.PEER_HOST_ENV: "dynabook",
            },
            hostname="linglong",
        )
        self.assertIn("--on dynabook", note)

    def test_a_dispatched_login_says_nothing(self):
        """It is already opening where the user asked; the note would mislead."""
        self.assertIsNone(
            remote.ssh_hint(
                {
                    "SSH_CONNECTION": "100.64.0.2 51234 100.64.0.1 22",
                    remote.DISPATCH_ENV: "1",
                },
                hostname="dynabook",
            )
        )

    def test_a_malformed_ssh_connection_is_not_a_session(self):
        self.assertIsNone(remote.ssh_hint({"SSH_CONNECTION": "   "}))


class TestWindowLocation(unittest.TestCase):
    """`get --show` waits for a human, so it has to say which screen to go to.

    The terminal and the window are routinely on different machines here, and
    "complete the challenge in the window" is useless to someone whose window
    is elsewhere.
    """

    def test_it_names_the_host_even_when_that_is_the_local_one(self):
        self.assertEqual(remote.window_screen("linglong"), "on linglong's screen")

    def test_there_is_no_caveat_outside_an_ssh_session(self):
        self.assertIsNone(remote.window_note({}))

    def test_over_ssh_it_says_that_is_not_where_you_are_typing(self):
        said = remote.window_note({"SSH_CONNECTION": "100.64.0.2 51234 100.64.0.1 22"})
        self.assertIn("100.64.0.2", said)
        self.assertIn("not the machine you are typing on", said)

    def test_it_suggests_no_hop_because_get_has_none(self):
        """`login --on` moves the sign-in; a clearance cookie cannot move."""
        said = remote.window_note(
            {"SSH_CONNECTION": "100.64.0.2 51234 100.64.0.1 22",
             remote.PEER_HOST_ENV: "dynabook"}
        )
        self.assertNotIn("--on", said)


class _Capture:
    def __init__(self) -> None:
        self.text = ""

    def write(self, chunk: str) -> int:
        self.text += chunk
        return len(chunk)

    def flush(self) -> None:
        pass


class TestLoginCommand(unittest.TestCase):
    """The CLI seam: which path `login` takes, and what it prints on the way."""

    def _args(self, **kwargs):
        return argparse.Namespace(
            **{
                "on": None,
                "timeout": 900.0,
                "ozone_platform": None,
                "verbose": False,
                **kwargs,
            }
        )

    def _login(self, args, environ):
        """cmd_login with the browser unreachable: only the dispatch seam runs."""
        with mock.patch.dict("os.environ", environ, clear=True):
            with mock.patch("sys.stderr", new_callable=_Capture) as err:
                with mock.patch.object(kcl_fetch, "_display") as display:
                    display.side_effect = AssertionError("would have opened a window")
                    try:
                        status = kcl_fetch.cmd_login(args, mock.Mock())
                    except AssertionError:
                        status = None
        return status, err.text

    def test_on_dispatches_over_ssh_and_returns_the_remote_status(self):
        with mock.patch.object(remote, "dispatch_login", return_value=5) as sent:
            status, err = self._login(self._args(on="dynabook", timeout=30.0), {})
        self.assertEqual(status, 5)
        self.assertIn("dynabook", err)
        self.assertEqual(sent.call_args.args, ("dynabook",))
        self.assertEqual(sent.call_args.kwargs["timeout"], 30.0)

    def test_on_with_no_value_uses_the_baked_in_peer(self):
        with mock.patch.object(remote, "dispatch_login", return_value=0) as sent:
            status, _ = self._login(
                self._args(on=remote.PEER), {remote.PEER_HOST_ENV: "dynabook"}
            )
        self.assertEqual(status, 0)
        self.assertEqual(sent.call_args.args, ("dynabook",))

    def test_on_with_no_value_and_no_peer_fails_before_ssh(self):
        with mock.patch.object(remote, "dispatch_login") as sent:
            status, err = self._login(self._args(on=remote.PEER), {})
        self.assertEqual(status, 2)
        sent.assert_not_called()
        self.assertIn("--on HOST", err)

    def test_an_unreachable_host_adds_one_line_and_keeps_the_status(self):
        with mock.patch.object(remote, "dispatch_login", return_value=255):
            status, err = self._login(self._args(on="dynabook"), {})
        self.assertEqual(status, 255)
        self.assertIn("never reached dynabook", err)

    def test_a_missing_ssh_is_reported_as_one_line(self):
        with mock.patch.object(
            remote, "dispatch_login", side_effect=remote.RemoteError("no `ssh` on PATH")
        ):
            status, err = self._login(self._args(on="dynabook"), {})
        self.assertEqual(status, 2)
        self.assertIn("no `ssh` on PATH", err)

    def test_an_ssh_session_gets_the_note_before_the_window_opens(self):
        status, err = self._login(
            self._args(), {"SSH_CONNECTION": "100.64.0.2 51234 100.64.0.1 22"}
        )
        self.assertIsNone(status)  # stopped at the display probe, note already out
        self.assertIn("SSH session from 100.64.0.2", err)

    def test_no_ssh_session_means_no_note_and_the_usual_path(self):
        status, err = self._login(self._args(), {})
        self.assertIsNone(status)
        self.assertEqual(err, "")

    def test_login_without_on_never_reaches_ssh(self):
        with mock.patch.object(remote, "dispatch_login") as sent:
            self._login(self._args(), {})
        sent.assert_not_called()


class TestParser(unittest.TestCase):
    def setUp(self) -> None:
        self.parser = kcl_fetch.build_parser()

    def test_on_takes_a_host(self):
        self.assertEqual(self.parser.parse_args(["login", "--on", "dyna"]).on, "dyna")

    def test_on_alone_stands_for_the_peer(self):
        self.assertIs(self.parser.parse_args(["login", "--on"]).on, remote.PEER)

    def test_on_alone_before_another_flag_still_stands_for_the_peer(self):
        args = self.parser.parse_args(["login", "--on", "--verbose"])
        self.assertIs(args.on, remote.PEER)
        self.assertTrue(args.verbose)

    def test_the_default_is_a_local_login(self):
        self.assertIsNone(self.parser.parse_args(["login"]).on)

    def test_only_login_hops(self):
        """`get` writes a PDF; running it elsewhere would file it elsewhere."""
        with self.assertRaises(SystemExit):
            with mock.patch("sys.stderr", new_callable=_Capture):
                self.parser.parse_args(["get", "10.1000/x", "--on", "dyna"])

    def test_the_help_names_the_peer_when_one_is_configured(self):
        with mock.patch.dict("os.environ", {remote.PEER_HOST_ENV: "dynabook"}):
            help_text = _login_help(kcl_fetch.build_parser())
        self.assertIn("dynabook", help_text)


def _login_help(parser) -> str:
    """The `login` subparser's own help text, without exiting the process."""
    for action in parser._subparsers._group_actions:
        choices = getattr(action, "choices", None) or {}
        if "login" in choices:
            return choices["login"].format_help()
    raise AssertionError("no login subparser")


if __name__ == "__main__":
    unittest.main()
