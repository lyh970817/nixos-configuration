"""A private X server, so `get` is invisible without being headless.

Headless Chromium is the single strongest bot signal a publisher SP looks for,
and this session carries an institutional identity (see `driver.py`). So the
fix for "a window pops up on my screen every fetch" is not to hide the browser
-- it is to hide the *screen*. An Xvfb server is started for the life of one
`get`, the same headed Chromium is launched on it with `--ozone-platform=x11`,
and the fingerprint is exactly the one that already worked while nothing
appears on any monitor.

`login` is the deliberate exception and keeps the real display: MFA means a
human has to see the window and answer the Authenticator prompt.

Two things make the lifecycle honest rather than hopeful:

* The display number comes from Xvfb itself, over `-displayfd`. Picking a free
  `:N` ourselves is a race against every other X client on the machine, and
  losing it silently attaches the browser to *someone else's* server -- which
  on this machine is the user's own screen.
* Nothing here falls back. No Xvfb means one line and a non-zero exit: falling
  back to the real display would paint the window we were asked to suppress,
  and falling back to headless would trade the visible window for the bot
  signal the whole design exists to avoid.
"""

from __future__ import annotations

import atexit
import os
import select
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from . import display as display_mod

#: Baked in by the Nix wrapper, like `$KCL_FETCH_CHROMIUM`.
XVFB_ENV = "KCL_FETCH_XVFB"

XVFB_BINARY = "Xvfb"

#: A desktop-sized screen. Publishers serve a responsive layout, and on a
#: narrow one the "Download PDF" control folds into a menu the selectors in
#: `driver.py` do not click.
SCREEN = "1920x1080x24"

START_TIMEOUT = 15.0
STOP_TIMEOUT = 5.0


class XvfbUnavailable(RuntimeError):
    """No usable Xvfb. A fact about the machine, printed as one line."""


def resolve_binary(configured: str | None = None, environ=None, which=shutil.which) -> str:
    environ = os.environ if environ is None else environ
    for candidate in (configured, environ.get(XVFB_ENV)):
        if candidate and Path(candidate).exists():
            return candidate
    found = which(XVFB_BINARY)
    if found:
        return found
    raise XvfbUnavailable(
        f"no {XVFB_BINARY} on PATH and ${XVFB_ENV} names none, so `get` cannot "
        "run on a virtual display -- install xorg.xvfb, or pass --show to run "
        "on your own screen (a window will appear)."
    )


class VirtualDisplay:
    """One Xvfb server, started on `start()` and always reaped.

    `stop()` is idempotent and is reached three ways: `__exit__` on the normal
    path and on any exception (`KeyboardInterrupt` from SIGINT included, since
    it unwinds the `with` like anything else), and `atexit` for the paths that
    leave without unwinding.
    """

    def __init__(
        self,
        *,
        binary: str | None = None,
        screen: str = SCREEN,
        timeout: float = START_TIMEOUT,
        spawn=subprocess.Popen,
        environ=None,
    ):
        self.binary = binary or resolve_binary(environ=environ)
        self.screen = screen
        self.timeout = timeout
        self._spawn = spawn
        self.process = None
        self.display: display_mod.Display | None = None
        self._log = None

    # -- lifecycle -------------------------------------------------------

    def start(self) -> display_mod.Display:
        read_fd, write_fd = os.pipe()
        # A temporary file rather than a pipe: nothing drains Xvfb's stderr
        # while the fetch runs, and a full pipe would block the X server. The
        # file has no name to clean up -- it is unlinked at creation.
        self._log = tempfile.TemporaryFile()
        argv = [
            self.binary,
            "-displayfd", str(write_fd),
            "-screen", "0", self.screen,
            "-nolisten", "tcp",
            # Keep the server up between clients: Chromium's zygote comes and
            # goes, and a resetting server would take the display with it.
            "-noreset",
        ]
        try:
            self.process = self._spawn(
                argv,
                pass_fds=(write_fd,),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=self._log,
            )
        except OSError as exc:
            os.close(read_fd)
            os.close(write_fd)
            self._close_log()
            raise XvfbUnavailable(f"could not start {self.binary}: {exc}") from None
        # Ours must go, or the read below never sees EOF when Xvfb dies.
        os.close(write_fd)
        try:
            number = self._read_display_number(read_fd)
        finally:
            os.close(read_fd)
        atexit.register(self.stop)
        self.display = display_mod.virtual_x11(
            number, f"Xvfb :{number} {self.screen}, started by kcl-fetch"
        )
        return self.display

    def stop(self) -> None:
        process, self.process = self.process, None
        if process is not None:
            try:
                process.terminate()
                process.wait(timeout=STOP_TIMEOUT)
            except Exception:
                try:
                    process.kill()
                    process.wait(timeout=STOP_TIMEOUT)
                except Exception:
                    pass
        self._close_log()
        atexit.unregister(self.stop)

    def __enter__(self) -> "VirtualDisplay":
        self.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        self.stop()
        return False

    # -- internals -------------------------------------------------------

    def _read_display_number(self, fd: int) -> int:
        """Xvfb writes the display number and a newline once it is listening."""
        deadline = time.monotonic() + self.timeout
        buffer = b""
        while b"\n" not in buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                self.stop()
                raise XvfbUnavailable(
                    f"{self.binary} did not report a display within "
                    f"{self.timeout:g}s"
                )
            if not select.select([fd], [], [], remaining)[0]:
                continue
            chunk = os.read(fd, 64)
            if not chunk:
                break
            buffer += chunk
        text = buffer.decode("ascii", "replace").strip()
        if not text.isdigit():
            detail = self._log_tail()
            self.stop()
            raise XvfbUnavailable(
                f"{self.binary} exited without opening a display{detail}"
            )
        return int(text)

    def _log_tail(self) -> str:
        if self._log is None:
            return ""
        try:
            self._log.seek(0)
            lines = self._log.read().decode("utf-8", "replace").strip().splitlines()
        except Exception:
            return ""
        return f" ({lines[-1].strip()})" if lines else ""

    def _close_log(self) -> None:
        if self._log is not None:
            try:
                self._log.close()
            except Exception:
                pass
            self._log = None
