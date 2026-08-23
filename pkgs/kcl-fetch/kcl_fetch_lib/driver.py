"""The browser. Ours, not an MCP server's.

`playwright-mcp` is the obvious-looking shortcut and it does not work for this:
it has no first-class download-retrieval tool (upstream #154, #953), and
Playwright deletes downloaded files when the browsing context closes -- so by
the time an agent could ask for the file, the file is gone. Owning the context
means owning `expect_download` and `save_as`, which is the whole job.

Three things are not negotiable:

* **Headed.** Headless Chromium is the single strongest bot signal a publisher
  SP looks for, and this session carries an institutional identity.
* **nixpkgs `chromium` via `executable_path`.** Playwright's own browser
  downloads are prebuilt glibc binaries that cannot run on NixOS. The nixpkgs
  `python3Packages.playwright` is patched to point at `playwright-core`'s
  `cli.js` for the driver, so only the browser needs supplying.
* **A dedicated profile.** MFA (Microsoft Entra) makes scripted login
  impossible, so the design is one manual human login reused until it expires.
  That means a long-lived cookie jar holding an institutional session -- it
  gets its own profile directory and never the user's everyday one.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import socket
import time
from dataclasses import dataclass, field
from pathlib import Path

from . import paths
from .pdfcheck import PdfFacts, validate
from .urls import KCL_IDP_ENTITY_ID, host_of

#: Hosts that mean "you are being asked to authenticate", not "here is the
#: article". The Entra ones are where KCL's MFA prompt actually lives.
LOGIN_HOSTS = (
    "login.microsoftonline.com",
    "login.microsoft.com",
    "kclidp.kcl.ac.uk",
    "login.openathens.net",
    "connect.openathens.net",
    "idp.kcl.ac.uk",
    "shibboleth.kcl.ac.uk",
    "signin.kcl.ac.uk",
    "msftauth.net",
)

_LOGIN_TEXT_RE = re.compile(
    r"(?i)\b(sign in to your account|enter your password|approve (the )?sign[- ]in "
    r"request|use your (institutional|organisational) )"
)

#: Anchors and buttons that lead to the full text on the publishers KCL uses.
PDF_SELECTORS = (
    "a[href$='.pdf']",
    "a[href*='/pdf']",
    "a[href*='pdfdirect']",
    "a[href*='epdf']",
    "a[data-track-action*='pdf' i]",
    "a[aria-label*='PDF' i]",
    "a[title*='PDF' i]",
    "a:has-text('Download PDF')",
    "a:has-text('View PDF')",
    "a:has-text('Full text PDF')",
    "button:has-text('Download PDF')",
)


class DriverError(RuntimeError):
    pass


class LoginRequired(DriverError):
    """The session is absent or expired; only a human can fix it."""

    def __init__(self, url: str):
        super().__init__(
            "KCL sign-in required (MFA is enforced, so this cannot be scripted). "
            "Run `kcl-fetch login`, complete sign-in and the Authenticator "
            "prompt in the window that opens, then retry."
        )
        self.url = url


class AccessForbidden(DriverError):
    """HTTP 403 from the publisher. Recorded, never retried."""

    def __init__(self, url: str, status: int = 403):
        super().__init__(f"{host_of(url)} answered {status}")
        self.url = url
        self.status = status


class NoFullText(DriverError):
    """Reached the article page, found no PDF we are entitled to."""


class StaleProfileLock(DriverError):
    """Chromium refused to start over a lock left by a process that is gone."""


#: Chromium's single-instance guard, written into the profile at startup and
#: normally reclaimed on the next run. `SingletonLock` is a symlink whose
#: *target* -- not content -- is `hostname-pid`.
SINGLETON_ENTRIES = ("SingletonLock", "SingletonCookie", "SingletonSocket")

#: "The caller took no before-picture." Distinct from `None`, which is a
#: before-picture showing no lock at all.
_NO_SNAPSHOT = object()


def singleton_target(profile_dir: Path) -> str | None:
    """What `SingletonLock` points at, or None if there is no lock."""
    try:
        return os.readlink(Path(profile_dir) / "SingletonLock")
    except OSError:
        return None


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # Someone else's process, but a process. Not stale.
        return True
    except OSError:
        return True
    return True


def stale_singleton_advice(profile_dir: Path, *, before=_NO_SNAPSHOT) -> str | None:
    """A message naming a stale lock, or None if the lock is absent or live.

    `before` is `singleton_target` as it read *before* the launch that failed.
    It matters more than it looks: a Chromium that dies for an unrelated reason
    -- no display, a bad flag -- still writes its own `SingletonLock` on the way
    down, and that lock's pid is dead the moment we look at it. Without the
    before-picture every launch failure would be misdiagnosed as a stale lock,
    which is exactly the opposite of a legible error.

    Deliberately advisory. This profile is the institutional session and one
    bad `rm` costs a fresh MFA round trip, so nothing here deletes anything --
    it tells the user which entries to remove and stops.
    """
    target = singleton_target(profile_dir)
    if target is None:
        return None
    if before is not _NO_SNAPSHOT and before != target:
        return None
    host, _, pid_text = target.rpartition("-")
    if not pid_text.isdigit():
        return None
    # A lock from another machine (a synced or copied profile) says nothing
    # about a pid on this one, so it is left alone.
    if host and host != socket.gethostname():
        return None
    if _pid_alive(int(pid_text)):
        return None
    listed = "\n".join(f"  {Path(profile_dir) / name}" for name in SINGLETON_ENTRIES)
    return (
        f"Chromium would not start, and the profile holds a stale lock "
        f"(SingletonLock -> {target}, pid {pid_text} is gone).\n"
        f"Nothing is deleted automatically -- this profile holds the "
        f"institutional session. Remove these yourself and retry:\n{listed}"
    )


@dataclass
class Fetched:
    path: Path
    facts: PdfFacts
    final_url: str
    template: str
    provenance: dict = field(default_factory=dict)


def _looks_like_login(page) -> bool:
    if host_of(page.url) in LOGIN_HOSTS:
        return True
    if any(page.url.startswith(f"https://{h}") for h in LOGIN_HOSTS):
        return True
    try:
        body = page.inner_text("body", timeout=2000)
    except Exception:
        return False
    return bool(_LOGIN_TEXT_RE.search(body))


class Browser:
    """A headed persistent Chromium, held open for the life of one command."""

    def __init__(
        self,
        *,
        profile_dir: Path,
        chromium: str,
        downloads_dir: Path,
        slow_mo: float = 0.0,
        extra_args: tuple[str, ...] = (),
        env: dict[str, str] | None = None,
    ):
        self.profile_dir = Path(profile_dir)
        self.chromium = chromium
        self.downloads_dir = Path(downloads_dir)
        self.slow_mo = slow_mo
        # nixpkgs chromium picks its ozone platform from the session; a
        # display-less harness (Xvfb, CI) has to say `--ozone-platform=x11`.
        self.extra_args = tuple(extra_args)
        # Display variables the caller probed for (see `display.py`). They are
        # layered over our own environment rather than replacing it, because
        # Playwright's `env=` is the browser's *whole* environment -- passing
        # only these two would strip PATH, HOME and the rest.
        self.env = dict(env or {})
        self._playwright = None
        self.context = None

    def __enter__(self) -> "Browser":
        from playwright.sync_api import sync_playwright

        # 0700, enforced rather than inherited from the umask: this directory
        # is the institutional session. What Chromium writes *inside* it is
        # Chromium's business; the containing directory is the boundary.
        paths.ensure(self.profile_dir)
        paths.ensure(self.downloads_dir)
        # Read before the attempt: only a lock that was already here can be the
        # thing that stopped us.
        lock_before = singleton_target(self.profile_dir)
        self._playwright = sync_playwright().start()
        try:
            self.context = self._playwright.chromium.launch_persistent_context(
                user_data_dir=str(self.profile_dir),
                executable_path=self.chromium,
                headless=False,
                accept_downloads=True,
                downloads_path=str(self.downloads_dir),
                slow_mo=self.slow_mo,
                viewport={"width": 1280, "height": 900},
                args=["--no-first-run", "--no-default-browser-check", *self.extra_args],
                env={**os.environ, **self.env},
                # Playwright passes `--enable-automation` by default, which sets
                # `navigator.webdriver` and the "controlled by automated software"
                # banner. Running headed to avoid looking like a bot and then
                # announcing it in the UA surface would be self-defeating; this is
                # one human's reading session, and it should look like one.
                ignore_default_args=["--enable-automation"],
            )
        except Exception as exc:
            advice = stale_singleton_advice(self.profile_dir, before=lock_before)
            if self._playwright is not None:
                self._playwright.stop()
                self._playwright = None
            if advice is not None:
                raise StaleProfileLock(advice) from exc
            raise
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        try:
            if self.context is not None:
                self.context.close()
        finally:
            if self._playwright is not None:
                self._playwright.stop()
        return False

    def page(self):
        return self.context.pages[0] if self.context.pages else self.context.new_page()

    # -- login -----------------------------------------------------------

    def interactive_login(self, start_url: str, *, wait_seconds: float = 900.0) -> bool:
        """Show the window and wait for the human to finish SSO.

        Returns True once the browser lands somewhere that is not an
        authentication host. There is no automation here on purpose: MFA means
        the only supported login is a person looking at the screen.
        """
        page = self.page()
        page.goto(start_url, wait_until="domcontentloaded")
        deadline = time.monotonic() + wait_seconds
        while time.monotonic() < deadline:
            if not _looks_like_login(page):
                return True
            page.wait_for_timeout(2000)
        return False

    # -- fetching --------------------------------------------------------

    def fetch_pdf(self, access_url: str, *, doi: str, template: str,
                  out_dir: Path, stem: str, min_bytes: int) -> Fetched:
        """Navigate an institutional access URL and capture the article PDF."""
        page = self.page()
        response = page.goto(access_url, wait_until="domcontentloaded", timeout=60000)

        if response is not None and response.status == 403:
            raise AccessForbidden(page.url, 403)
        if _looks_like_login(page):
            raise LoginRequired(page.url)

        download = self._trigger_download(page)
        if download is None:
            raise NoFullText(
                f"no downloadable PDF on {page.url} -- KCL may not hold this "
                "article, or the link is behind a purchase option"
            )

        # The output directory is the user's, chosen with `-o`, so its mode is
        # left alone. The two files written into it are ours, and are not.
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        target = out_dir / f"{stem}.pdf"
        download.save_as(str(target))
        paths.secure_file(target)
        facts = validate(target, min_bytes=min_bytes)

        provenance = {
            "doi": doi,
            "access_template": template,
            "access_url": access_url,
            "final_url": page.url,
            "publisher_host": host_of(page.url),
            "idp_entity_id": KCL_IDP_ENTITY_ID,
            "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "bytes": facts.size,
            "pages": facts.pages,
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        }
        sidecar = target.with_suffix(".provenance.json")
        sidecar.write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")
        paths.secure_file(sidecar)
        return Fetched(target, facts, page.url, template, provenance)

    def _trigger_download(self, page):
        """The page may already *be* the PDF, or hide it behind one link.

        At most one click happens: the first selector that matches anything
        wins, and if that click yields no download we stop. Walking every
        candidate selector would be a handful of publisher requests for one
        article, which is exactly the traffic shape the gate exists to prevent
        -- and the gate cannot see clicks inside a page it already admitted.
        """
        download = self._download_current_pdf(page)
        if download is not None:
            return download

        for selector in PDF_SELECTORS:
            locator = page.locator(selector).first
            try:
                if locator.count() == 0:
                    continue
            except Exception:
                continue
            try:
                with page.expect_download(timeout=60000) as info:
                    locator.click(timeout=15000)
                return info.value
            except Exception:
                # The click may have navigated to an inline PDF viewer instead
                # of downloading. That is the same one request, so reading it
                # out costs nothing more.
                return self._download_current_pdf(page)
        return None

    @staticmethod
    def _download_current_pdf(page):
        if not page.url.lower().split("?")[0].endswith(".pdf"):
            return None
        try:
            with page.expect_download(timeout=60000) as info:
                page.reload()
            return info.value
        except Exception:
            return None
