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
import re
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
    ):
        self.profile_dir = Path(profile_dir)
        self.chromium = chromium
        self.downloads_dir = Path(downloads_dir)
        self.slow_mo = slow_mo
        # nixpkgs chromium picks its ozone platform from the session; a
        # display-less harness (Xvfb, CI) has to say `--ozone-platform=x11`.
        self.extra_args = tuple(extra_args)
        self._playwright = None
        self.context = None

    def __enter__(self) -> "Browser":
        from playwright.sync_api import sync_playwright

        # 0700, enforced rather than inherited from the umask: this directory
        # is the institutional session. What Chromium writes *inside* it is
        # Chromium's business; the containing directory is the boundary.
        paths.ensure(self.profile_dir)
        paths.ensure(self.downloads_dir)
        self._playwright = sync_playwright().start()
        self.context = self._playwright.chromium.launch_persistent_context(
            user_data_dir=str(self.profile_dir),
            executable_path=self.chromium,
            headless=False,
            accept_downloads=True,
            downloads_path=str(self.downloads_dir),
            slow_mo=self.slow_mo,
            viewport={"width": 1280, "height": 900},
            args=["--no-first-run", "--no-default-browser-check", *self.extra_args],
            # Playwright passes `--enable-automation` by default, which sets
            # `navigator.webdriver` and the "controlled by automated software"
            # banner. Running headed to avoid looking like a bot and then
            # announcing it in the UA surface would be self-defeating; this is
            # one human's reading session, and it should look like one.
            ignore_default_args=["--enable-automation"],
        )
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
