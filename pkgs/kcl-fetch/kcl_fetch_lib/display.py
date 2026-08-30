"""Which display Chromium should talk to, decided by probing, not by trust.

The environment a tool is *invoked* from is not always the environment its
graphical session lives in. A shell started outside the session -- a systemd
unit, an agent harness, a detached multiplexer -- can have `XDG_RUNTIME_DIR`,
`WAYLAND_DISPLAY` and `DISPLAY` all unset while Hyprland is running two feet
away and both its sockets sit on disk. Reading only `$WAYLAND_DISPLAY` and
concluding "no Wayland, use x11" then lands on the one platform that also has
no variable set, and Chromium dies with `Missing X server or $DISPLAY`.

So the sockets are the source of truth and the variables are only a hint. What
is found is handed back as the variables Chromium needs, because Chromium reads
the same environment we just declined to trust -- `XDG_RUNTIME_DIR` in
particular, without which it cannot find a Wayland socket we located ourselves.

When nothing is there, that is a fact about the user's session, not a crash:
`NoDisplay` carries one line of advice and no traceback.
"""

from __future__ import annotations

import os
import re
import stat
from dataclasses import dataclass, field
from pathlib import Path

#: Where X's abstract-namespace-less sockets live. A constant so tests can
#: point it at a tmpdir instead of the real one.
X11_SOCKET_DIR = Path("/tmp/.X11-unix")

#: Where `$XDG_RUNTIME_DIR` would have pointed had it been set. Also a constant
#: for the tests, which have to reproduce "the variable is missing but the
#: directory is there" without a real per-uid runtime directory.
RUNTIME_DIR_TEMPLATE = "/run/user/{uid}"

#: `X0`, `X1`, ... and nothing else. Chromium's `:N` maps to exactly this, and
#: the directory routinely holds neighbours (`X0_`, lock files) that are not
#: displays.
_X_SOCKET_RE = re.compile(r"^X(\d+)$")

_WAYLAND_PREFIX = "wayland-"

#: The one variable a virtual X display has to withdraw. See `virtual_x11`.
WAYLAND_VAR = "WAYLAND_DISPLAY"


class NoDisplay(RuntimeError):
    """No graphical session to attach to. A user-environment problem."""


@dataclass(frozen=True)
class Display:
    """A platform to ask Chromium for, and the variables that make it work."""

    platform: str
    #: Merged over the parent environment when the browser is launched. Never
    #: exported into this process: the browser's environment is the only one
    #: that needs repairing.
    env: dict[str, str] = field(default_factory=dict)
    #: One line, for `--verbose`. Says what was probed, not what was assumed.
    detail: str = ""
    #: Variables to *remove* from the browser's environment. Setting `DISPLAY`
    #: is not enough on a Wayland desktop: the session's `WAYLAND_DISPLAY` is
    #: inherited too, and leaving it in place is the one way a launch aimed at
    #: a private X server can still find its way onto the user's screen.
    unset: tuple[str, ...] = ()

    def ozone_args(self) -> tuple[str, ...]:
        return (f"--ozone-platform={self.platform}",)


def virtual_x11(number: int, detail: str) -> Display:
    """The display for an X server this process started itself (`xvfb.py`).

    Not probed, because there is nothing to probe: we know the number, we know
    it is X, and we know the session's Wayland socket must not be reachable
    from it.
    """
    return Display("x11", {"DISPLAY": f":{number}"}, detail, unset=(WAYLAND_VAR,))


def _is_socket(path: Path) -> bool:
    """A real AF_UNIX socket, by mode -- not by name.

    Load-bearing: `wayland-1.lock` is a regular file sitting right beside
    `wayland-1`, and a `wayland-*` glob happily matches both.
    """
    try:
        return stat.S_ISSOCK(os.stat(path).st_mode)
    except OSError:
        return False


def runtime_dir(environ=None) -> Path | None:
    """`$XDG_RUNTIME_DIR`, or the conventional per-uid directory if it exists."""
    environ = os.environ if environ is None else environ
    configured = environ.get("XDG_RUNTIME_DIR")
    if configured:
        return Path(configured)
    fallback = Path(RUNTIME_DIR_TEMPLATE.format(uid=os.getuid()))
    return fallback if fallback.is_dir() else None


def _sort_key(name: str, prefix: str) -> tuple[int, int | str]:
    """Lowest-numbered first, unnumbered names after them, both deterministic."""
    suffix = name[len(prefix):]
    return (0, int(suffix)) if suffix.isdigit() else (1, name)


def _wayland_sockets(rt: Path) -> list[str]:
    try:
        names = os.listdir(rt)
    except OSError:
        return []
    found = [
        name
        for name in names
        if name.startswith(_WAYLAND_PREFIX) and _is_socket(rt / name)
    ]
    return sorted(found, key=lambda name: _sort_key(name, _WAYLAND_PREFIX))


def _x_displays(socket_dir: Path | None = None) -> list[tuple[int, Path]]:
    socket_dir = X11_SOCKET_DIR if socket_dir is None else socket_dir
    try:
        names = os.listdir(socket_dir)
    except OSError:
        return []
    found = []
    for name in names:
        match = _X_SOCKET_RE.match(name)
        if match and _is_socket(socket_dir / name):
            found.append((int(match.group(1)), socket_dir / name))
    return sorted(found)


def _wayland(rt: Path | None, name: str, detail: str) -> Display:
    env = {"WAYLAND_DISPLAY": name}
    # Chromium resolves a relative $WAYLAND_DISPLAY against $XDG_RUNTIME_DIR,
    # so naming the socket without naming its directory finds nothing.
    if rt is not None:
        env["XDG_RUNTIME_DIR"] = str(rt)
    return Display("wayland", env, detail)


def detect_wayland(environ=None, rt: Path | None = None) -> Display | None:
    environ = os.environ if environ is None else environ
    rt = runtime_dir(environ) if rt is None else rt

    # (b) The variable is believed only once its socket has been seen.
    named = environ.get("WAYLAND_DISPLAY")
    if named:
        candidate = Path(named)
        if not candidate.is_absolute() and rt is not None:
            candidate = rt / named
        if _is_socket(candidate):
            return _wayland(rt, named, f"$WAYLAND_DISPLAY={named} ({candidate})")

    # (c) Otherwise take the lowest-numbered socket actually on disk.
    if rt is not None:
        sockets = _wayland_sockets(rt)
        if sockets:
            chosen = sockets[0]
            others = f", ignoring {', '.join(sockets[1:])}" if len(sockets) > 1 else ""
            return _wayland(rt, chosen, f"wayland socket {rt / chosen}{others}")
    return None


def detect_x11(environ=None, *, x11_dir: Path | None = None) -> Display | None:
    environ = os.environ if environ is None else environ

    # (d) An existing $DISPLAY is taken as given -- it may name a remote X
    # server, or a socket somewhere we would never think to look.
    display = environ.get("DISPLAY")
    if display:
        return Display("x11", {"DISPLAY": display}, f"$DISPLAY={display}")

    # (e) Otherwise the socket names the display: `X0` is `:0`.
    x_displays = _x_displays(x11_dir)
    if x_displays:
        number, path = x_displays[0]
        rest = [f":{n}" for n, _ in x_displays[1:]]
        others = f", ignoring {', '.join(rest)}" if rest else ""
        return Display("x11", {"DISPLAY": f":{number}"}, f"X socket {path}{others}")
    return None


def detect(environ=None, *, x11_dir: Path | None = None) -> Display:
    """Probe for a usable display. Raises `NoDisplay` when there is none.

    Wayland first: on a Wayland session XWayland is usually up as well, so
    preferring X would work but would put the browser through a translation
    layer the desktop does not otherwise use.
    """
    environ = os.environ if environ is None else environ
    rt = runtime_dir(environ)
    for found in (detect_wayland(environ, rt), detect_x11(environ, x11_dir=x11_dir)):
        if found is not None:
            return found
    raise NoDisplay(_no_display_advice(rt, x11_dir))


def _no_display_advice(rt: Path | None, x11_dir: Path | None) -> str:
    where = str(rt) if rt is not None else "$XDG_RUNTIME_DIR (unset)"
    x_where = X11_SOCKET_DIR if x11_dir is None else x11_dir
    return (
        f"no display found (no Wayland socket in {where}, no X socket in "
        f"{x_where}). Run this from your graphical session, or pass "
        "--ozone-platform."
    )


def resolve(explicit: str | None = None, environ=None, *,
            x11_dir: Path | None = None) -> Display:
    """The platform to use, with an explicit `--ozone-platform` winning.

    An explicit choice is honoured even when nothing was detected for it -- the
    user may be starting a compositor, or know something the probe cannot.

    It is still probed *for that platform specifically*, not for the platform
    detection would have picked. `--ozone-platform x11` on a Wayland desktop
    has to arrive with `DISPLAY` set from the XWayland socket, or forcing x11
    would fail for exactly the reason the caller was trying to work around.
    """
    environ = os.environ if environ is None else environ
    if not explicit:
        return detect(environ, x11_dir=x11_dir)
    probe = {
        "wayland": lambda: detect_wayland(environ),
        "x11": lambda: detect_x11(environ, x11_dir=x11_dir),
    }.get(explicit)
    found = probe() if probe is not None else None
    if found is None:
        return Display(explicit, {}, f"--ozone-platform={explicit} (forced, unprobed)")
    return Display(
        explicit,
        dict(found.env),
        f"--ozone-platform={explicit} (forced; {found.detail})",
    )
