"""The browser. Ours, not an MCP server's.

`playwright-mcp` is the obvious-looking shortcut and it does not work for this:
it has no first-class download-retrieval tool (upstream #154, #953), and
Playwright deletes downloaded files when the browsing context closes -- so by
the time an agent could ask for the file, the file is gone. Owning the context
means owning `expect_download` and `save_as`, which is the whole job.

Three things are not negotiable:

* **Headed.** Headless Chromium is the single strongest bot signal a publisher
  SP looks for, and this session carries an institutional identity. `get` still
  launches headed; it is the *screen* that is virtual (see `xvfb.py`), so
  nothing appears on a monitor and the fingerprint is unchanged.
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
import urllib.parse
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

#: Path shapes that *are* the PDF although the path does not end in `.pdf`.
#: ScienceDirect is the standing example: its "Download PDF" control points at
#: `/science/article/pii/<PII>/pdfft?isDTMRedir=true&download=true`, an
#: intermediate that redirects to the file on `pdf.sciencedirectassets.com`.
#: Wiley (`/doi/epdf/`, `/doi/pdfdirect/`) and the OUP/Silverchair family
#: (`/article-pdf/`) are the same idea with different spellings.
PDF_URL_MARKERS = (
    "/pdfft",
    "/epdf/",
    "/pdfdirect",
    "/doi/pdf",
    "/article-pdf",
    "/content/pdf",
)

#: Markup that only ever belongs to a bot-defence interstitial. Elsevier serves
#: Cloudflare Turnstile *at the article URL*, wrapped in ScienceDirect's own
#: header and footer -- so the URL, the host and the chrome all still say
#: "article page" while the content is a captcha.
CHALLENGE_SELECTORS = (
    "script[src*='challenges.cloudflare.com']",
    "iframe[src*='challenges.cloudflare.com']",
    "input[name='cf-turnstile-response']",
    "[id^='cf-chl-widget']",
    "#cf-challenge-running",
    "form#challenge-form",
    "#captcha-box",
    "#px-captcha",
    "iframe[src*='hcaptcha.com']",
    "iframe[src*='recaptcha']",
)

#: How often to look at a page a human is working on -- signing in, or
#: answering a challenge. Reading the DOM costs no request, and neither a
#: person typing a password nor one clicking a checkbox is in a hurry.
HUMAN_POLL_MS = 2000

_CHALLENGE_TITLE_RE = re.compile(
    r"(?i)^\s*(just a moment|attention required|one moment,? please|"
    r"access denied|security check|verifying you are human)"
)

_CHALLENGE_TEXT_RE = re.compile(
    r"(?i)(are you a robot|confirm you are a human|verify (that )?you are "
    r"(a )?human|checking your browser before|enable javascript and cookies "
    r"to continue|complete the security check|unusual traffic from your)"
)

#: Text that means the publisher is *offering to sell* the article -- the one
#: page state that really is an answer about KCL's entitlement.
_PAYWALL_TEXT_RE = re.compile(
    r"(?i)(get access\b|purchase pdf|purchase access|purchase this (article|chapter)"
    r"|buy (this )?article|rent this article|subscribe to (this )?journal"
    r"|access through your (institution|organisation|organization))"
)


class DriverError(RuntimeError):
    pass


class LoginRequired(DriverError):
    """The route ended at an authentication wall, not at the article.

    Kept strictly distinct from `NoFullText`, because the two send the user to
    opposite places. This one means the stored session lapsed and a human has
    to sign in again; `NoFullText` means we *reached* the publisher and KCL's
    entitlement did not cover the article, which is a question for the library.
    Reporting the first as the second is a wild goose chase over a cookie.
    """

    def __init__(self, url: str):
        self.url = url
        self.host = host_of(url) or url
        super().__init__(
            f"stopped at the sign-in wall on {self.host} -- the stored KCL "
            "session has expired, so no publisher was reached and nothing was "
            "learned about KCL's entitlement."
        )


class AccessForbidden(DriverError):
    """HTTP 403 from the publisher. Recorded, never retried."""

    def __init__(self, url: str, status: int = 403):
        super().__init__(f"{host_of(url)} answered {status}")
        self.url = url
        self.status = status


class BotChallenge(DriverError):
    """The publisher answered with "are you a robot", not with the article.

    A third thing, distinct from both `LoginRequired` and `NoFullText`, and the
    one that is easiest to misfile as either. Elsevier serves a Cloudflare
    Turnstile captcha *at the article URL*, inside ScienceDirect's own header
    and footer: `page.url` is the article, `host_of(page.url)` is the
    publisher, and there is no PDF anywhere on it. Read as an entitlement
    verdict that is "KCL may not hold this article" -- about an article whose
    page we never actually saw.

    Nothing here solves it. A captcha exists to be answered by a human, and
    answering one programmatically is precisely the behaviour it is asking
    about; the honest move is to say what happened and hand the window over --
    which, when there is a screen to hand it over on, is what `await_challenge`
    does. This exception is what is left when there is not, or when the offer
    was made and nobody took it.

    `waited` is that second case: the number of seconds the window was held
    open on a real screen before giving up. `None` means it was never held
    open, because there was no screen to hold it open on.
    """

    def __init__(self, url: str, signature: str = "", *, waited: float | None = None):
        self.url = url
        self.host = host_of(url) or url
        self.signature = signature
        self.waited = waited
        detail = f" ({signature})" if signature else ""
        unanswered = (
            f" The window was held open for {waited:g}s and the challenge was "
            "not completed."
            if waited is not None
            else ""
        )
        super().__init__(
            f"reached {self.host} and was served a human-verification "
            f"challenge{detail} instead of the article, on {url} -- this is "
            f"bot defence, and says nothing about KCL's entitlement.{unanswered}"
        )


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


@dataclass
class Capture:
    """The PDF in hand, however we came by it.

    Two ways in, because publishers use both. A `download` is Playwright's own
    object, from a response Chromium treated as an attachment. `data` is the
    bytes read back through the context's cookie jar, which is what is left
    when Chromium decides to *render* the PDF in its built-in viewer instead:
    an inline render fires no download event, so `expect_download` waits out
    its timeout over a PDF that is already on screen.
    """

    download: object | None = None
    data: bytes | None = None
    source_url: str = ""

    @classmethod
    def of(cls, value) -> "Capture":
        return value if isinstance(value, cls) else cls(download=value)

    def save_as(self, target: Path) -> None:
        if self.download is not None:
            self.download.save_as(str(target))
        else:
            Path(target).write_bytes(self.data or b"")


def is_login_host(url: str) -> bool:
    """True when this URL is an authentication host, subdomains included.

    Exact matching alone misses the entries that are written as parents on
    purpose: Entra serves its assets and some of its prompts from
    `*.msftauth.net`, and a Shibboleth deployment moves between `idp.` names.
    """
    host = host_of(url)
    if not host:
        return False
    return any(host == known or host.endswith(f".{known}") for known in LOGIN_HOSTS)


def _looks_like_login(page) -> bool:
    if is_login_host(page.url):
        return True
    try:
        body = page.inner_text("body", timeout=2000)
    except Exception:
        return False
    return bool(_LOGIN_TEXT_RE.search(body))


def looks_like_pdf_url(url: str) -> bool:
    """Is this URL the file itself rather than a page about it?

    The `.pdf` suffix alone is not the test. Every large publisher now serves
    the file from a path that carries no extension -- `pdfft`, `epdf`,
    `pdfdirect`, `article-pdf` -- and a suffix-only check walks straight past
    all of them.
    """
    path = urllib.parse.urlsplit(url).path.casefold()
    return path.endswith(".pdf") or any(m in path for m in PDF_URL_MARKERS)


def challenge_signature(page) -> str | None:
    """A short name for the interstitial on this page, or None.

    Two independent lines of evidence, because either alone is thin: the
    widget markup a challenge provider has to put in the DOM, and the sentence
    the page shows a human. Both are read out of the page we already loaded --
    no extra request is made to decide this.
    """
    for selector in CHALLENGE_SELECTORS:
        try:
            if page.locator(selector).count() > 0:
                return f"{selector} present"
        except Exception:
            continue
    try:
        title = page.title()
    except Exception:
        title = ""
    if title and _CHALLENGE_TITLE_RE.search(title):
        return f"page title {title.strip()!r}"
    try:
        body = page.inner_text("body", timeout=2000)
    except Exception:
        return None
    found = _CHALLENGE_TEXT_RE.search(body)
    return f"page says {found.group(0)!r}" if found else None


def has_pdf_control(page) -> bool:
    """Does anything on this page look like a way to the full text?

    Used only to keep the challenge check honest: a page carrying a real PDF
    control is a page we should try to capture from, whatever else is embedded
    in it. Pure DOM inspection, no clicks.
    """
    for selector in PDF_SELECTORS:
        try:
            if page.locator(selector).count() > 0:
                return True
        except Exception:
            continue
    return False


def offers_purchase(page) -> bool:
    """Is the publisher offering to sell us this article?

    The only page state that is genuinely an answer about entitlement. Absence
    of a PDF is not: a page can lack one because it is still rendering,
    because the control has a shape we do not recognise, or because we were
    never shown the article at all.
    """
    try:
        body = page.inner_text("body", timeout=2000)
    except Exception:
        return False
    return bool(_PAYWALL_TEXT_RE.search(body))


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
        env_unset: tuple[str, ...] = (),
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
        # Variables to drop rather than set. A private X server needs the
        # session's `WAYLAND_DISPLAY` gone, not overridden.
        self.env_unset = tuple(env_unset)
        self._playwright = None
        self.context = None

    def browser_env(self) -> dict[str, str]:
        merged = {**os.environ, **self.env}
        for name in self.env_unset:
            merged.pop(name, None)
        return merged

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
                env=self.browser_env(),
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

    def interactive_login(
        self,
        start_url: str,
        *,
        wait_seconds: float = 900.0,
        target_host: str | None = None,
    ) -> bool:
        """Show the window and wait for the human to finish SSO.

        There is no automation here on purpose: MFA means the only supported
        login is a person looking at the screen. What this *does* decide is
        when that person is finished, and "we are not currently on a login
        host" is not that test. `start_url` is the OpenAthens redirector, which
        is not a login host either -- so the old condition was already true on
        the first poll, before a single hop had run, and a `login` that
        established nothing could report success. The evidence for that is a
        profile holding Entra cookies and no live OpenAthens session.

        Finished therefore means: the chain has settled, we are not on a login
        host, and we got here honestly -- either at `target_host`, the page we
        actually asked the redirector for, or by having passed through a login
        wall on the way (the case where the session was already good is the
        first; the case where the human just signed in is either).
        """
        page = self.page()
        page.goto(start_url, wait_until="domcontentloaded")
        started_on = host_of(start_url)
        deadline = time.monotonic() + wait_seconds
        saw_wall = False
        while True:
            self._settle(page, timeout=5000)
            here = host_of(page.url)
            if _looks_like_login(page):
                saw_wall = True
            elif target_host and (here == target_host
                                  or here.endswith(f".{target_host}")):
                return True
            elif saw_wall and here != started_on:
                return True
            if time.monotonic() >= deadline:
                return False
            page.wait_for_timeout(HUMAN_POLL_MS)

    # -- challenges ------------------------------------------------------

    def await_challenge(
        self,
        page,
        signature: str,
        *,
        wait_seconds: float = 0.0,
        announce=None,
    ) -> None:
        """Hold the window open while a human answers the challenge.

        The same bargain as `interactive_login`, one publisher-defence layer
        along: nothing is automated, a person looks at the screen, and all this
        decides is when they are finished. Nothing here touches the widget --
        answering a captcha programmatically is exactly the behaviour it is
        asking about.

        `wait_seconds <= 0` means there is no screen to wait on -- `get` paints
        on a private Xvfb server unless `--show`, and nobody can answer a
        challenge on a display nobody is looking at. Then this is just the
        raise it always was.

        Finished means two consecutive polls, each after the load state has
        settled, that find no challenge signature *and* the same URL. One clear
        poll is not enough: clearance is a navigation, and the moment between
        the widget leaving the DOM and the real page arriving reads as clear
        while showing nothing. Requiring the URL to hold still across two polls
        is what "settled on something that is no longer a challenge" means
        here; the caller then captures from that page as usual.
        """
        if wait_seconds <= 0:
            raise BotChallenge(page.url, signature)
        if announce is not None:
            announce(signature)
        deadline = time.monotonic() + wait_seconds
        cleared_at: str | None = None
        while True:
            self._settle(page, timeout=5000)
            if challenge_signature(page) is None:
                if cleared_at is not None and cleared_at == page.url:
                    return
                cleared_at = page.url
            else:
                cleared_at = None
            if time.monotonic() >= deadline:
                raise BotChallenge(page.url, signature, waited=wait_seconds)
            page.wait_for_timeout(HUMAN_POLL_MS)

    # -- fetching --------------------------------------------------------

    def fetch_pdf(self, access_url: str, *, doi: str, template: str,
                  out_dir: Path, stem: str, min_bytes: int,
                  challenge_wait: float = 0.0, on_challenge=None) -> Fetched:
        """Navigate an institutional access URL and capture the article PDF.

        `challenge_wait` is how long a human has to answer a bot challenge in
        the window, and is nonzero only when there is a window they can see
        (`get --show`). It defaults to zero, so every caller that has not
        thought about it keeps the old behaviour: report the challenge and
        stop.
        """
        page = self.page()
        response = page.goto(access_url, wait_until="domcontentloaded", timeout=60000)

        if response is not None and response.status == 403:
            raise AccessForbidden(page.url, 403)
        self._settle(page)
        if _looks_like_login(page):
            raise LoginRequired(page.url)
        # Before any clicking. A captcha page is the last place to start
        # clicking things, and the guard against a false positive is not
        # subtlety in the detector but the PDF control itself: a page that
        # offers the full text is a page to capture from, whatever is embedded
        # alongside it.
        signature = challenge_signature(page)
        if signature and not has_pdf_control(page):
            # Waits when a person can see the window, raises when nobody can.
            # Returning means the challenge is gone and this page is now the
            # article, so the capture below runs on it -- no second navigation,
            # and no second gated request.
            self.await_challenge(
                page,
                signature,
                wait_seconds=challenge_wait,
                announce=on_challenge,
            )

        capture = self._trigger_download(page)
        if capture is None:
            # Checked again, and this is the check that actually fires in
            # practice. An SSO hop is a JS auto-POST, not an HTTP redirect, so
            # `domcontentloaded` returns on the *form*, several hops before
            # Entra; the login wall only becomes visible once the chain has
            # run. Without this, an expired session is reported as "KCL may not
            # hold this article" -- an entitlement verdict from a browser that
            # never reached the publisher.
            if _looks_like_login(page):
                raise LoginRequired(page.url)
            # Same reasoning one step later: a challenge can also arrive on the
            # navigation a click caused, after the first page looked ordinary.
            late = challenge_signature(page)
            if late:
                self.await_challenge(
                    page,
                    late,
                    wait_seconds=challenge_wait,
                    announce=on_challenge,
                )
                # Answered. The click that ran into the challenge captured
                # nothing, so the control is tried once more on the page that
                # was actually served -- once, not in a loop, for the same
                # reason `_trigger_download` clicks once.
                capture = self._trigger_download(page)

        if capture is None:
            # The old message said "KCL may not hold this article" for every
            # empty page, which is a verdict about a subscription drawn from
            # the absence of a link. Only a purchase offer is evidence of that;
            # everything else is us not finding the control, and the two send
            # the user to completely different places.
            if offers_purchase(page):
                raise NoFullText(
                    f"reached {host_of(page.url)} and the page offers a "
                    f"purchase or access option rather than the full text on "
                    f"{page.url} -- KCL's subscription does not appear to "
                    "cover this article"
                )
            raise NoFullText(
                f"reached {host_of(page.url)} and found neither a PDF control "
                f"nor a purchase option on {page.url} -- so this is a capture "
                "failure, not an entitlement verdict: the page may not have "
                "finished rendering, or its full-text control is one this tool "
                "does not recognise"
            )

        # The output directory is the user's, chosen with `-o`, so its mode is
        # left alone. The two files written into it are ours, and are not.
        capture = Capture.of(capture)
        out_dir = Path(out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        target = out_dir / f"{stem}.pdf"
        capture.save_as(target)
        paths.secure_file(target)
        facts = validate(target, min_bytes=min_bytes)

        provenance = {
            "doi": doi,
            "access_template": template,
            "access_url": access_url,
            "final_url": page.url,
            "pdf_url": capture.source_url or page.url,
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

    @staticmethod
    def _settle(page, timeout: int = 15000) -> None:
        """Let the SSO hops finish before anyone reads `page.url`.

        Costs no extra request -- it waits on the chain the navigation already
        started. Best effort: a page that keeps a socket open never reaches
        `networkidle`, and that is not a reason to fail a fetch.
        """
        try:
            page.wait_for_load_state("networkidle", timeout=timeout)
        except Exception:
            pass

    def _trigger_download(self, page):
        """The page may already *be* the PDF, or hide it behind one link.

        At most one click happens: the first selector that matches anything
        wins, and if that click yields no download we stop. Walking every
        candidate selector would be a handful of publisher requests for one
        article, which is exactly the traffic shape the gate exists to prevent
        -- and the gate cannot see clicks inside a page it already admitted.
        """
        article_url = page.url
        capture = self._capture_pdf_page(page)
        if capture is not None:
            return capture

        for selector in PDF_SELECTORS:
            locator = page.locator(selector).first
            try:
                if locator.count() == 0:
                    continue
            except Exception:
                continue
            try:
                href = locator.get_attribute("href", timeout=5000)
            except Exception:
                href = None
            try:
                with page.expect_download(timeout=60000) as info:
                    locator.click(timeout=15000)
                return Capture(download=info.value, source_url=page.url)
            except Exception:
                return self._capture_after_click(page, article_url, href)
        return None

    def _capture_pdf_page(self, page):
        """We are standing on the file. Get it off the screen and onto disk."""
        if not looks_like_pdf_url(page.url):
            return None
        try:
            with page.expect_download(timeout=60000) as info:
                page.reload()
            return Capture(download=info.value, source_url=page.url)
        except Exception:
            # Served inline rather than as an attachment, so no download event
            # ever fires. The bytes are still ours to ask for.
            return self._fetch_bytes(page, page.url)

    def _capture_after_click(self, page, article_url: str, href: str | None):
        """The click did something other than start a download. What?

        Three shapes, all of them ordinary and none of them a download event:
        the tab navigated to the file and Chromium rendered it inline, the
        control opened the file in a new tab, or the control was an anchor we
        can simply follow ourselves. Each candidate costs one request at most
        and the first PDF wins, so a click can never fan out into a burst.
        """
        seen: set[str] = set()
        for url in self._pdf_candidates(page, href):
            if url in seen:
                continue
            seen.add(url)
            capture = self._fetch_bytes(page, url, referer=article_url)
            if capture is not None:
                return capture
        return None

    @staticmethod
    def _pdf_candidates(page, href: str | None):
        if looks_like_pdf_url(page.url):
            yield page.url
        try:
            others = list(page.context.pages)
        except Exception:
            others = []
        for other in others:
            try:
                url = other.url
            except Exception:
                continue
            if url != page.url and looks_like_pdf_url(url):
                yield url
        if href:
            resolved = urllib.parse.urljoin(page.url, href)
            if looks_like_pdf_url(resolved):
                yield resolved

    @staticmethod
    def _fetch_bytes(page, url: str, *, referer: str | None = None):
        """Read a PDF through the browser context's own cookie jar.

        `context.request` carries the session -- the publisher SP cookie the
        whole OpenAthens hop exists to obtain -- so this is the same
        authenticated identity the tab has, not a second anonymous client. The
        `%PDF-` check here is a guard against saving an HTML error page under a
        `.pdf` name; the real validation still runs on the file (`pdfcheck`).
        """
        headers = {"Referer": referer} if referer else None
        try:
            response = page.context.request.get(url, headers=headers, timeout=60000)
            if not response.ok:
                return None
            body = response.body()
        except Exception:
            return None
        if not body.startswith(b"%PDF-"):
            return None
        return Capture(data=body, source_url=url)
