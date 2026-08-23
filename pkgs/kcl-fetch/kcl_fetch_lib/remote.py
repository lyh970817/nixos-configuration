"""Signing in on the machine the human is actually sitting at.

`login` opens a real Chromium window, and a window opens on the screen of the
host the *browser* runs on -- not the host the command was typed on. In an SSH
session those are two different machines, so a `login` typed on the laptop
while connected to the desktop paints a sign-in window nobody is in front of.

The fix is to move the sign-in, not the session. The profile under
`$XDG_DATA_HOME/kcl-fetch/profile` is per-host state on purpose -- each machine
holds its own institutional session and no cookie is ever copied between them
-- so `--on HOST` re-runs the *same* `kcl-fetch login` one SSH hop away, against
that host's own profile. Nothing here reimplements the login.

Detection of an SSH session only ever produces a note. Auto-dispatching on
`$SSH_CONNECTION` would open a browser on a machine the user did not name,
from a client address that need not map to a host we know; the default
behaviour is left exactly as it was.
"""

from __future__ import annotations

import os
import shlex
import socket
import subprocess

#: Baked in by the Nix wrapper from `portable.peerHost`. Unset is a supported
#: state: `--on` then requires an explicit host.
PEER_HOST_ENV = "KCL_FETCH_PEER_HOST"

#: Set on the *remote* invocation by the dispatch below. It marks "this login
#: was sent here deliberately", which is exactly the case where the SSH note
#: would be wrong -- the window is already opening where the user asked.
#: Carried as an environment variable rather than a flag so a peer running an
#: older build ignores it instead of dying on an unknown option.
DISPATCH_ENV = "KCL_FETCH_DISPATCHED"

#: The command to run on the far side. Home Manager installs it into
#: /etc/profiles/per-user/$USER/bin, which is on `PATH` for a non-interactive
#: `ssh host <cmd>` shell.
REMOTE_COMMAND = "kcl-fetch"

SSH = "ssh"

#: ssh's own reserved exit status: it never got as far as running the command.
#: Distinguished only to add one line of context; the status still propagates.
SSH_FAILURE_STATUS = 255


class RemoteError(RuntimeError):
    """A fact about the hop, not about the login. Printed as one line."""


class _Peer:
    """`--on` with no value: whichever machine is the other half of the pair."""

    def __repr__(self) -> str:  # shows up in argparse errors and test failures
        return "<peer>"


PEER = _Peer()


def peer_host(environ=None) -> str:
    environ = os.environ if environ is None else environ
    return environ.get(PEER_HOST_ENV, "").strip()


def resolve_host(value, environ=None) -> str:
    """The host `--on` names, with the bare flag standing for the peer."""
    if value is not PEER:
        host = str(value).strip()
        if not host:
            raise RemoteError("--on was given an empty host name")
        if host.startswith("-"):
            # Would be read as an ssh option rather than a destination.
            raise RemoteError(f"{host!r} is not a usable host name")
        return host
    peer = peer_host(environ)
    if not peer:
        raise RemoteError(
            f"--on was given no host and no peer is configured (${PEER_HOST_ENV} "
            "is unset). Name the machine: --on HOST."
        )
    return peer


def _number(value: float) -> str:
    """900.0 as `900`: it goes back through argparse's float on the far side."""
    return f"{value:g}"


def login_argv(
    host: str,
    *,
    timeout: float | None = None,
    ozone_platform: str | None = None,
    verbose: bool = False,
    tty: bool = False,
) -> list[str]:
    """`ssh HOST kcl-fetch login ...`, with this invocation's flags carried over.

    Each remote word is shell-quoted: ssh hands the command to a shell on the
    far side, which parses it a second time.
    """
    remote = [f"{DISPATCH_ENV}=1", REMOTE_COMMAND, "login"]
    if timeout is not None:
        remote += ["--timeout", _number(timeout)]
    if ozone_platform:
        remote += ["--ozone-platform", ozone_platform]
    if verbose:
        remote.append("--verbose")
    # `env` rather than a bare assignment so the prefix survives whichever
    # shell the remote account uses.
    remote.insert(0, "env")
    return [SSH, *(["-t"] if tty else []), host, *(shlex.quote(w) for w in remote)]


def dispatch_login(host: str, *, runner=subprocess.call, **flags) -> int:
    """Run the sign-in on `host` and return its exit status.

    The remote output is streamed rather than captured: the instructions and
    the final success or failure line are the whole point, and a failed remote
    login has to stay a failed local command.
    """
    argv = login_argv(host, **flags)
    try:
        return runner(argv)
    except FileNotFoundError:
        raise RemoteError(
            f"no `{SSH}` on PATH, so --on cannot reach {host}"
        ) from None
    except OSError as exc:
        raise RemoteError(f"could not run {SSH}: {exc}") from None


def ssh_client(environ=None) -> str | None:
    """The client address of the SSH session we are in, if we are in one.

    `$SSH_CONNECTION` is `client-ip client-port server-ip server-port`.
    """
    environ = os.environ if environ is None else environ
    fields = environ.get("SSH_CONNECTION", "").split()
    return fields[0] if fields else None


def ssh_hint(environ=None, hostname: str | None = None) -> str | None:
    """One note when the window would open on the far end of the SSH session.

    The client address is reported as the fact it is, and the peer is named
    only as the argument to try -- not as a claim about where the user is
    sitting. A client IP does not reliably identify a host we know, and a
    confidently wrong host name is worse than a generic one.
    """
    environ = os.environ if environ is None else environ
    if environ.get(DISPATCH_ENV):
        return None
    client = ssh_client(environ)
    if not client:
        return None
    here = socket.gethostname() if hostname is None else hostname
    peer = peer_host(environ)
    suggestion = (
        f"`kcl-fetch login --on {peer}` (or just `--on`)"
        if peer
        else "`kcl-fetch login --on HOST`"
    )
    return (
        f"kcl-fetch: note -- this is an SSH session from {client}, so the "
        f"window below opens on {here}'s screen,\n"
        "  not on the machine you are sitting at. To sign in where you are, "
        f"run {suggestion}."
    )
