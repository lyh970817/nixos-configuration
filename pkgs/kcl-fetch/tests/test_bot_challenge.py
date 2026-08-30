"""A captcha is not a subscription gap either.

The observed failure, on `10.1016/j.jad.2024.01.106`, with a KCL session that
was working at the time:

    kcl-fetch: openathens route failed -- reached sciencedirect.com and found
    no downloadable PDF on https://www.sciencedirect.com/science/article/pii/
    S0165032724001174?via%3Dihub -- KCL may not hold this article, or the link
    is behind a purchase option

Instrumenting one live load of that exact URL showed what was actually on the
page: `<title>Just a moment...</title>`, an `<h1>` reading "Are you a robot?",
`Please confirm you are a human by completing the captcha challenge below.`, a
Cloudflare Turnstile widget (`challenges.cloudflare.com/turnstile/v0/...`,
`input[name="cf-turnstile-response"]`, `#captcha-box`) -- and, of the eleven
`PDF_SELECTORS`, zero matches. No "Download PDF", no "View PDF", and equally no
"Get Access" and no "Purchase PDF": the page carried ScienceDirect's own header
and footer, so the host and the URL both still read as the article, but the
article was never served at all.

That is a third outcome, and both existing ones swallowed it. It is not a login
wall -- no login host, no sign-in text, and signing in again fixes nothing. It
is not an entitlement verdict -- nothing about KCL's holdings was tested. The
message printed was the entitlement verdict, which is the wild goose chase
`LoginRequired` was introduced to stop, one publisher-defence layer further
along.
"""

from __future__ import annotations

import argparse
import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import kcl_fetch
from kcl_fetch_lib import config as config_mod
from kcl_fetch_lib import display as display_mod
from kcl_fetch_lib import driver as driver_mod
from kcl_fetch_lib import gate as gate_mod
from kcl_fetch_lib import metadata
from kcl_fetch_lib.pdfcheck import NotAPdf
from support import GateFixture

DOI = "10.1016/j.jad.2024.01.106"
ARTICLE = (
    "https://www.sciencedirect.com/science/article/pii/S0165032724001174?via%3Dihub"
)
PDFFT = (
    "https://www.sciencedirect.com/science/article/pii/S0165032724001174/pdfft"
    "?isDTMRedir=true&download=true"
)
ASSET = (
    "https://pdf.sciencedirectassets.com/271623/1-s2.0-S0165032724001174"
    "/1-s2.0-S0165032724001174-main.pdf?X-Amz-Signature=deadbeef"
)

#: The three things the live page really had in it.
TURNSTILE = (
    "script[src*='challenges.cloudflare.com']",
    "input[name='cf-turnstile-response']",
    "#captcha-box",
)

CHALLENGE_BODY = (
    "Are you a robot?\n"
    "Please confirm you are a human by completing the captcha challenge below.\n"
    "Reference number: a33329b7cc5f1e11\n"
    "About ScienceDirect\nRemote access\nContact and support"
)


def pdf_bytes(pages: int = 14, padding: int = 4096) -> bytes:
    body = b"%PDF-1.7\n1 0 obj\n<< /Type /Pages /Kids [] /Count "
    body += str(pages).encode("ascii") + b" >>\nendobj\n"
    return body + b"%" + b"x" * padding + b"\n%%EOF\n"


# ---------------------------------------------------------------------------
# A page with just enough Playwright in it


class FakeDownload:
    def __init__(self, data: bytes | None = None):
        self.data = pdf_bytes() if data is None else data

    def save_as(self, path: str) -> None:
        Path(path).write_bytes(self.data)


class FakeExpect:
    """`expect_download`, which times out when nothing downloads."""

    def __init__(self, page: "FakePage"):
        self.page = page

    def __enter__(self) -> "FakeExpect":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        if exc_type is not None:
            return False
        if self.page.download is None:
            raise TimeoutError("no download event")
        return False

    @property
    def value(self) -> FakeDownload:
        return self.page.download


class FakeLocator:
    def __init__(self, page: "FakePage", present: bool):
        self.page = page
        self.present = present

    @property
    def first(self) -> "FakeLocator":
        return self

    def count(self) -> int:
        return 1 if self.present else 0

    def get_attribute(self, name: str, timeout=None):
        return self.page.href if name == "href" else None

    def click(self, timeout=None) -> None:
        self.page.clicks += 1
        if self.page.click_navigates_to is not None:
            self.page.url = self.page.click_navigates_to
        if self.page.click_opens is not None:
            self.page.context.pages.append(FakePage(self.page.click_opens))


class FakeRequest:
    """`context.request` -- the same cookie jar as the tab."""

    def __init__(self, page: "FakePage"):
        self.page = page

    def get(self, url: str, headers=None, timeout=None):
        self.page.requested.append((url, dict(headers or {})))
        body = self.page.resources.get(url)
        return type(
            "FakeResponse",
            (),
            {"ok": body is not None, "body": staticmethod(lambda: body or b"")},
        )()


class FakeContext:
    def __init__(self, page: "FakePage"):
        self.pages = [page]
        self.request = FakeRequest(page)


class FakePage:
    """Enough Playwright page to walk every branch of the capture path."""

    def __init__(
        self,
        url: str = ARTICLE,
        *,
        title: str = "Sleep and depression - ScienceDirect",
        body: str = "Abstract\nHighlights\nGet rights and content",
        markup: tuple[str, ...] = (),
        controls: tuple[str, ...] = (),
        href: str | None = None,
        download: FakeDownload | None = None,
        click_navigates_to: str | None = None,
        click_opens: str | None = None,
        resources: dict[str, bytes] | None = None,
    ):
        self.url = url
        self._title = title
        self.body = body
        self.markup = set(markup)
        self.controls = set(controls)
        self.href = href
        self.download = download
        self.click_navigates_to = click_navigates_to
        self.click_opens = click_opens
        self.resources = dict(resources or {})
        self.context = FakeContext(self)
        self.clicks = 0
        self.requested: list[tuple[str, dict]] = []

    # -- navigation ------------------------------------------------------

    def goto(self, url, **kwargs):
        return type("Response", (), {"status": 200})()

    def reload(self) -> None:
        pass

    def wait_for_load_state(self, state, timeout=None) -> None:
        pass

    # -- reading ---------------------------------------------------------

    def title(self) -> str:
        return self._title

    def inner_text(self, selector, timeout=None) -> str:
        return self.body

    def locator(self, selector: str) -> FakeLocator:
        return FakeLocator(self, selector in self.markup or selector in self.controls)

    def expect_download(self, **kwargs) -> FakeExpect:
        return FakeExpect(self)


def browser_over(page: FakePage) -> driver_mod.Browser:
    browser = driver_mod.Browser(
        profile_dir=Path(tempfile.mkdtemp()),
        chromium="/nonexistent/chromium",
        downloads_dir=Path(tempfile.mkdtemp()),
    )
    browser.page = lambda: page
    return browser


def fetch(page: FakePage, *, out_dir: Path | None = None, min_bytes: int = 1024,
          **kwargs):
    return browser_over(page).fetch_pdf(
        "https://go.openathens.net/redirector/kcl.ac.uk?url=x",
        doi=DOI,
        template="openathens",
        out_dir=out_dir or Path(tempfile.mkdtemp()),
        stem="10.1016_j.jad.2024.01.106",
        min_bytes=min_bytes,
        **kwargs,
    )


# ---------------------------------------------------------------------------


class TestTheObservedPage(unittest.TestCase):
    def page(self) -> FakePage:
        return FakePage(
            ARTICLE, title="Just a moment...", body=CHALLENGE_BODY, markup=TURNSTILE
        )

    def test_the_captcha_is_recognised_for_what_it_is(self):
        self.assertIsNotNone(driver_mod.challenge_signature(self.page()))

    def test_it_is_reported_as_bot_defence_not_as_a_holdings_verdict(self):
        with self.assertRaises(driver_mod.BotChallenge) as caught:
            fetch(self.page())
        message = str(caught.exception)
        self.assertIn("human-verification challenge", message)
        self.assertIn("sciencedirect.com", message)
        self.assertNotIn("may not hold", message)
        self.assertNotIn("sign-in wall", message)

    def test_nothing_is_clicked_on_a_captcha_page(self):
        page = self.page()
        with self.assertRaises(driver_mod.BotChallenge):
            fetch(page)
        self.assertEqual(page.clicks, 0)
        self.assertEqual(page.requested, [])

    def test_the_title_alone_would_have_been_enough(self):
        """`Just a moment...` is never an article page."""
        page = FakePage(ARTICLE, title="Just a moment...", body="")
        self.assertIn("Just a moment", driver_mod.challenge_signature(page) or "")

    def test_so_would_the_sentence_alone(self):
        """A provider can change its widget; it still has to ask the question."""
        page = FakePage(ARTICLE, title="ScienceDirect", body=CHALLENGE_BODY)
        self.assertIn("robot", driver_mod.challenge_signature(page) or "")

    def test_a_challenge_is_not_a_login_wall(self):
        self.assertFalse(driver_mod.is_login_host(ARTICLE))


class TestNotEverythingIsACaptcha(unittest.TestCase):
    def test_an_ordinary_article_page_is_not_challenged(self):
        self.assertIsNone(driver_mod.challenge_signature(FakePage(ARTICLE)))

    def test_an_article_about_robots_is_not_challenged(self):
        page = FakePage(ARTICLE, body="Abstract\nRobotic surgery outcomes in 2024")
        self.assertIsNone(driver_mod.challenge_signature(page))

    def test_a_page_that_offers_the_pdf_is_captured_from_regardless(self):
        """The guard against a false positive is the PDF control itself.

        A widget somewhere in the markup of a page that is also offering the
        full text must not abort the fetch: capture first, diagnose only when
        there is nothing to capture.
        """
        page = FakePage(
            ARTICLE,
            title="Just a moment...",
            markup=TURNSTILE,
            controls=("a[href*='/pdf']",),
            download=FakeDownload(),
        )
        result = fetch(page)
        self.assertEqual(page.clicks, 1)
        self.assertEqual(result.facts.pages, 14)


class TestTheEntitlementVerdictIsNarrowed(unittest.TestCase):
    """"No link on the page" was never evidence about a subscription."""

    def message(self, page: FakePage) -> str:
        with self.assertRaises(driver_mod.NoFullText) as caught:
            fetch(page)
        return str(caught.exception)

    def test_a_purchase_offer_is_an_entitlement_answer(self):
        text = self.message(FakePage(ARTICLE, body="Get Access\nPurchase PDF $31.50"))
        self.assertIn("does not appear to cover", text)

    def test_an_empty_page_is_a_capture_failure_and_says_so(self):
        text = self.message(FakePage(ARTICLE, body="Abstract"))
        self.assertIn("capture failure, not an entitlement verdict", text)
        self.assertNotIn("may not hold", text)

    def test_the_two_messages_are_not_the_same_message(self):
        paywalled = self.message(FakePage(ARTICLE, body="Access through your institution"))
        empty = self.message(FakePage(ARTICLE, body="Abstract"))
        self.assertNotEqual(paywalled, empty)

    def test_a_challenge_that_only_appears_after_the_click_is_still_a_challenge(self):
        """Cloudflare can just as well interpose on the navigation the click causes."""
        page = FakePage(
            ARTICLE, controls=("a[href*='/pdf']",), click_navigates_to=ARTICLE
        )

        def challenge_on_click(target, timeout=None):
            target.body = CHALLENGE_BODY
            target.clicks += 1

        page.locator = lambda selector: _ClickInto(page, selector, challenge_on_click)
        with self.assertRaises(driver_mod.BotChallenge):
            fetch(page)


class _ClickInto(FakeLocator):
    """A locator whose click mutates the page instead of navigating it."""

    def __init__(self, page, selector, action):
        super().__init__(page, selector in page.controls)
        self.action = action

    def click(self, timeout=None) -> None:
        self.action(self.page)


class TestPdfUrlsWithoutAPdfSuffix(unittest.TestCase):
    """The suffix test walked straight past every large publisher."""

    def test_sciencedirects_pdfft_intermediate_counts(self):
        self.assertTrue(driver_mod.looks_like_pdf_url(PDFFT))

    def test_so_do_the_other_house_styles(self):
        for url in (
            "https://onlinelibrary.wiley.com/doi/epdf/10.1002/da.23456",
            "https://onlinelibrary.wiley.com/doi/pdfdirect/10.1002/da.23456",
            "https://academic.oup.com/schizbull/article-pdf/49/3/1/x.pdf",
            "https://link.springer.com/content/pdf/10.1007/s00.pdf",
        ):
            with self.subTest(url=url):
                self.assertTrue(driver_mod.looks_like_pdf_url(url))

    def test_a_signed_asset_url_with_a_query_still_counts(self):
        self.assertTrue(driver_mod.looks_like_pdf_url(ASSET))

    def test_an_article_landing_page_does_not(self):
        self.assertFalse(driver_mod.looks_like_pdf_url(ARTICLE))
        self.assertFalse(
            driver_mod.looks_like_pdf_url("https://doi.org/10.1016/j.jad.2024.01.106")
        )


class TestCaptureWhenChromiumRendersInsteadOfDownloading(unittest.TestCase):
    """No download event fires for a PDF Chromium decides to display.

    `expect_download` then waits out its timeout over a file that is already on
    the screen, and the old code read that timeout as "no PDF here".
    """

    def test_the_bytes_are_read_back_through_the_session(self):
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            href="/science/article/pii/S0165032724001174/pdfft?isDTMRedir=true",
            click_navigates_to=PDFFT,
            resources={PDFFT: pdf_bytes()},
        )
        result = fetch(page)
        self.assertEqual(result.facts.pages, 14)
        self.assertEqual(result.path.read_bytes()[:5], b"%PDF-")

    def test_the_publisher_is_told_which_page_sent_us(self):
        """Elsevier's asset host checks the referer; an empty one 403s."""
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            click_navigates_to=ASSET,
            resources={ASSET: pdf_bytes()},
        )
        fetch(page)
        self.assertEqual(page.requested[0][1]["Referer"], ARTICLE)

    def test_a_pdf_opened_in_a_new_tab_is_found(self):
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            click_opens=PDFFT,
            resources={PDFFT: pdf_bytes()},
        )
        self.assertEqual(fetch(page).facts.pages, 14)

    def test_an_anchor_that_did_nothing_at_all_is_followed(self):
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            href="/science/article/pii/S0165032724001174/pdfft?download=true",
            resources={PDFFT.replace("?isDTMRedir=true&download=true", "?download=true"):
                       pdf_bytes()},
        )
        self.assertEqual(fetch(page).facts.pages, 14)

    def test_an_html_error_page_is_not_saved_as_a_pdf(self):
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            click_navigates_to=PDFFT,
            resources={PDFFT: b"<html>Access denied</html>"},
        )
        with self.assertRaises(driver_mod.NoFullText):
            fetch(page)

    def test_one_click_is_still_one_click(self):
        """The fallbacks must not turn a miss into a burst of requests."""
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            href="/science/article/pii/S0165032724001174/pdfft",
            click_navigates_to=PDFFT,
        )
        with self.assertRaises(driver_mod.NoFullText):
            fetch(page)
        self.assertEqual(page.clicks, 1)
        self.assertLessEqual(len(page.requested), 2)

    def test_a_download_event_is_still_preferred_when_there_is_one(self):
        page = FakePage(
            ARTICLE, controls=("a[href*='/pdf']",), download=FakeDownload()
        )
        fetch(page)
        self.assertEqual(page.requested, [])


class TestValidationSurvivesTheNewPath(unittest.TestCase):
    """Bytes fetched by hand go through exactly the checks a download does."""

    def test_a_single_page_stub_is_still_rejected(self):
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            click_navigates_to=PDFFT,
            resources={PDFFT: pdf_bytes(pages=1)},
        )
        with self.assertRaises(NotAPdf):
            fetch(page)

    def test_the_size_floor_is_still_enforced(self):
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            click_navigates_to=PDFFT,
            resources={PDFFT: pdf_bytes(padding=8)},
        )
        with self.assertRaises(NotAPdf):
            fetch(page)

    def test_the_provenance_sidecar_records_where_the_file_came_from(self):
        out = Path(tempfile.mkdtemp())
        page = FakePage(
            ARTICLE,
            controls=("a[href*='/pdf']",),
            click_navigates_to=PDFFT,
            resources={PDFFT: pdf_bytes()},
        )
        result = fetch(page, out_dir=out)
        self.assertEqual(result.provenance["pdf_url"], PDFFT)
        self.assertTrue(result.path.with_suffix(".provenance.json").exists())


class TestGateAccounting(unittest.TestCase):
    """The opposite call from a login wall, for the opposite reason."""

    def setUp(self) -> None:
        self.fixture = GateFixture()
        self.addCleanup(self.fixture.close)

    def test_a_challenge_spends_budget_because_it_was_real_traffic(self):
        with self.fixture.gate.acquire("sciencedirect.com", DOI) as attempt:
            attempt.challenged("turnstile")
        self.assertEqual(self.fixture.gate.budget_state()["short"][0], 1)

    def test_it_is_written_to_the_ledger_under_its_own_name(self):
        with self.fixture.gate.acquire("sciencedirect.com", DOI) as attempt:
            attempt.challenged("cf-turnstile-response present")
        row = self.fixture.gate.recent(1)[0]
        self.assertEqual(row["outcome"], gate_mod.CHALLENGE_OUTCOME)
        self.assertIn("turnstile", row["detail"])

    def test_the_outcome_is_deliberately_inside_the_spending_set(self):
        self.assertIn(gate_mod.CHALLENGE_OUTCOME, gate_mod.SPENDING_OUTCOMES)

    def test_it_is_not_filed_as_a_miss(self):
        self.assertNotEqual(gate_mod.CHALLENGE_OUTCOME, "miss")


# ---------------------------------------------------------------------------
# Answering it, which is what --show is for
#
# The message above told the user to rerun with `--show` and complete the
# challenge in the window. Reproduced on the laptop, that command opened a
# window on the real display, detected the challenge, and exited -- the window
# vanished before anyone could click anything. The advice was impossible to
# follow with the tool that printed it.


class FakeTime:
    """`time.monotonic` under test control; the page's waits move it.

    Nothing sleeps: a fifteen-minute window is walked through in whatever a
    poll loop costs in Python. Anything else `driver` asks the real `time`
    module for (`strftime`, in the provenance sidecar) is delegated.
    """

    def __init__(self, start: float = 1000.0):
        self.t = start

    def monotonic(self) -> float:
        return self.t

    def advance(self, seconds: float) -> None:
        self.t += seconds

    def __getattr__(self, name):
        import time as real_time

        return getattr(real_time, name)


ARTICLE_TITLE = "Sleep and depression - ScienceDirect"
ARTICLE_BODY = "Abstract\nHighlights\nGet rights and content"
PDF_CONTROL = "a[href*='/pdf']"
INTERSTITIAL = "https://www.sciencedirect.com/science/article/pii/S0165032724001174"


class _WatchedLocator(FakeLocator):
    """Records whether a click happened while the challenge was still up."""

    def click(self, timeout=None) -> None:
        if not self.page.cleared:
            self.page.clicks_while_challenged += 1
        super().click(timeout=timeout)


class ChallengedPage(FakePage):
    """The Turnstile page, with a human on the other side of the screen.

    `_settle` is the poll, so `wait_for_load_state` counts them and
    `clears_after` is how many a person takes to click the checkbox. Clearing
    does what a real clearance does: the widget leaves the DOM, the title and
    the body become the article's, and the PDF control that was never served
    finally appears.
    """

    def __init__(self, clock: FakeTime, *, clears_after: int | None = None,
                 urls_after_clearing: tuple[str, ...] = (), **kwargs):
        super().__init__(
            ARTICLE,
            title="Just a moment...",
            body=CHALLENGE_BODY,
            markup=TURNSTILE,
            **kwargs,
        )
        self.clock = clock
        self.clears_after = clears_after
        self.urls_after_clearing = list(urls_after_clearing)
        self.polls = 0
        self.waited = 0
        self.clicks_while_challenged = 0

    @property
    def cleared(self) -> bool:
        return not self.markup

    def wait_for_load_state(self, _state, timeout=None) -> None:
        self.polls += 1
        if self.clears_after is not None and self.polls > self.clears_after:
            self.clear()

    def wait_for_timeout(self, ms) -> None:
        self.waited += 1
        self.clock.advance(ms / 1000.0)

    def clear(self) -> None:
        self.markup = set()
        self._title = ARTICLE_TITLE
        self.body = ARTICLE_BODY
        self.controls = {PDF_CONTROL}
        self.download = FakeDownload()
        if self.urls_after_clearing:
            self.url = self.urls_after_clearing.pop(0)

    def rechallenge(self) -> None:
        self.markup = set(TURNSTILE)
        self._title = "Just a moment..."
        self.body = CHALLENGE_BODY
        self.controls = set()
        self.download = None

    def locator(self, selector: str) -> FakeLocator:
        return _WatchedLocator(
            self, selector in self.markup or selector in self.controls
        )


class FlickeringPage(ChallengedPage):
    """Clearance is a navigation, and mid-navigation reads clear.

    One poll of "no widget" is not evidence that the challenge is over: between
    the widget leaving the DOM and the real page arriving there is a moment
    that looks exactly like success and is not.
    """

    rechallenges = 0

    def wait_for_load_state(self, _state, timeout=None) -> None:
        self.polls += 1
        if self.polls == 3:
            self.clear()
        elif self.polls == 4:
            self.rechallenge()
            self.rechallenges += 1
        elif self.polls >= 6:
            self.clear()


class LateChallengePage(ChallengedPage):
    """An ordinary article page; the click walks into the interstitial."""

    def __init__(self, clock: FakeTime, **kwargs):
        super().__init__(clock, **kwargs)
        self.clear()
        self.url = ARTICLE

    def locator(self, selector: str) -> FakeLocator:
        return _ClickIntoChallenge(
            self, selector in self.markup or selector in self.controls
        )


class _ClickIntoChallenge(_WatchedLocator):
    """The first click is met by the interstitial; the retry after it is not."""

    def click(self, timeout=None) -> None:
        super().click(timeout=timeout)
        if self.page.clicks == 1:
            self.page.rechallenge()


class TestTheWindowWaitsForTheHuman(unittest.TestCase):
    """`--show` says a person is looking at this window. So let them answer."""

    def setUp(self) -> None:
        self.clock = FakeTime()
        self.announced: list[str] = []
        patcher = mock.patch.object(driver_mod, "time", self.clock)
        patcher.start()
        self.addCleanup(patcher.stop)

    def fetch(self, page: FakePage, wait: float = 900.0):
        return fetch(
            page, challenge_wait=wait, on_challenge=self.announced.append
        )

    def test_the_fetch_carries_on_once_the_challenge_is_answered(self):
        page = ChallengedPage(self.clock, clears_after=2)
        result = self.fetch(page)
        self.assertEqual(result.facts.pages, 14)
        self.assertGreaterEqual(page.waited, 1)

    def test_it_is_the_page_already_loaded_that_is_captured_from(self):
        """No second navigation: the cleared page is the article, so use it."""
        page = ChallengedPage(self.clock, clears_after=2)
        self.fetch(page)
        self.assertEqual(page.clicks, 1)
        self.assertEqual(page.requested, [])

    def test_nothing_is_clicked_while_the_challenge_is_still_up(self):
        page = ChallengedPage(self.clock, clears_after=2)
        self.fetch(page)
        self.assertEqual(page.clicks_while_challenged, 0)

    def test_the_terminal_is_told_before_the_waiting_starts(self):
        page = ChallengedPage(self.clock, clears_after=2)
        self.fetch(page)
        self.assertEqual(len(self.announced), 1)
        self.assertIn("challenges.cloudflare.com", self.announced[0])

    def test_one_clear_poll_is_not_enough(self):
        page = FlickeringPage(self.clock)
        result = self.fetch(page)
        self.assertEqual(result.facts.pages, 14)
        self.assertEqual(page.rechallenges, 1)
        # A single-poll rule would have finished at poll 3, in the gap.
        self.assertGreaterEqual(page.polls, 6)
        self.assertEqual(page.clicks_while_challenged, 0)

    def test_it_waits_for_the_url_to_hold_still(self):
        """Clearance usually redirects, and the redirect target is the article."""
        page = ChallengedPage(
            self.clock, clears_after=1, urls_after_clearing=(INTERSTITIAL, ARTICLE)
        )
        result = self.fetch(page)
        self.assertEqual(result.final_url, ARTICLE)

    def test_a_challenge_that_arrives_after_the_click_is_handed_over_too(self):
        page = LateChallengePage(self.clock, clears_after=2)
        result = self.fetch(page)
        self.assertEqual(result.facts.pages, 14)
        self.assertEqual(page.clicks_while_challenged, 0)
        self.assertEqual(len(self.announced), 1)

    def test_an_unanswered_challenge_times_out_and_is_still_a_challenge(self):
        page = ChallengedPage(self.clock)
        with self.assertRaises(driver_mod.BotChallenge) as caught:
            self.fetch(page, wait=120.0)
        self.assertEqual(caught.exception.waited, 120.0)
        self.assertIn("not completed", str(caught.exception))

    def test_the_timeout_is_the_one_asked_for(self):
        page = ChallengedPage(self.clock)
        started = self.clock.t
        with self.assertRaises(driver_mod.BotChallenge):
            self.fetch(page, wait=120.0)
        self.assertGreaterEqual(self.clock.t - started, 120.0)
        self.assertLess(self.clock.t - started, 130.0)

    def test_a_timed_out_challenge_still_touches_nothing(self):
        page = ChallengedPage(self.clock)
        with self.assertRaises(driver_mod.BotChallenge):
            self.fetch(page, wait=10.0)
        self.assertEqual(page.clicks, 0)
        self.assertEqual(page.requested, [])


class TestWithoutAScreenNothingWaits(unittest.TestCase):
    """The Xvfb default is correct as it stands: nobody is looking at it.

    Waiting fifteen minutes for a human to answer a challenge on a display that
    exists only inside the process would be a fifteen-minute pause for nothing,
    with the gate lock held.
    """

    def setUp(self) -> None:
        self.clock = FakeTime()
        patcher = mock.patch.object(driver_mod, "time", self.clock)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_the_challenge_is_reported_at_once(self):
        page = ChallengedPage(self.clock, clears_after=2)
        with self.assertRaises(driver_mod.BotChallenge) as caught:
            fetch(page)
        self.assertIsNone(caught.exception.waited)

    def test_not_a_single_poll_is_spent(self):
        page = ChallengedPage(self.clock, clears_after=2)
        with self.assertRaises(driver_mod.BotChallenge):
            fetch(page)
        self.assertEqual(page.waited, 0)
        self.assertEqual(self.clock.t, 1000.0)

    def test_a_zero_timeout_is_the_same_as_no_screen(self):
        page = ChallengedPage(self.clock, clears_after=2)
        with self.assertRaises(driver_mod.BotChallenge):
            fetch(page, challenge_wait=0.0)
        self.assertEqual(page.waited, 0)


class TestTheCliSeam(unittest.TestCase):
    """Only `--show` puts the window somewhere a human can reach it."""

    def _fetch(self, *, show: bool, timeout: float = 900.0) -> dict:
        recorded: dict = {}

        class RecordingBrowser:
            def __init__(self, **kwargs):
                pass

            def __enter__(self):
                return self

            def __exit__(self, *exc):
                return False

            def fetch_pdf(self, _url, **kwargs):
                recorded.update(kwargs)
                raise driver_mod.BotChallenge(ARTICLE, "#captcha-box present")

        root = Path(tempfile.mkdtemp())
        args = argparse.Namespace(
            doi=DOI,
            output=str(root / "out"),
            show=show,
            timeout=timeout,
            ozone_platform=None,
            verbose=False,
        )
        env = {
            "XDG_STATE_HOME": str(root / "state"),
            "XDG_DATA_HOME": str(root / "data"),
            "XDG_CONFIG_HOME": str(root / "config"),
            "HOME": str(root),
            "PATH": os.environ.get("PATH", ""),
        }
        with mock.patch.dict("os.environ", env, clear=True):
            with mock.patch.object(kcl_fetch.libkey, "precheck", return_value=None):
                with mock.patch.object(
                    kcl_fetch.metadata,
                    "lookup",
                    return_value=metadata.Record(landing_url=ARTICLE),
                ):
                    with mock.patch.object(driver_mod, "Browser", RecordingBrowser):
                        with mock.patch("sys.stderr", new_callable=_Capture):
                            code = kcl_fetch._fetch(
                                args,
                                config_mod.Config(chromium=sys.executable),
                                display_mod.Display("x11", {}, "test"),
                            )
        self.assertEqual(code, 6)
        return recorded

    def test_show_hands_the_timeout_down_to_the_fetch(self):
        self.assertEqual(self._fetch(show=True, timeout=600.0)["challenge_wait"], 600.0)

    def test_without_show_the_wait_is_zero(self):
        self.assertEqual(self._fetch(show=False)["challenge_wait"], 0.0)


class TestTheAnnouncement(unittest.TestCase):
    """Said to a terminal that is often not on the machine with the window."""

    def announce(self) -> str:
        with mock.patch("sys.stderr", new_callable=_Capture) as err:
            kcl_fetch._announce_challenge("#captcha-box present", 900.0)
        return err.text

    def test_it_names_the_machine_the_window_is_on(self):
        self.assertIn(socket.gethostname(), self.announce())

    def test_it_says_it_is_waiting_and_for_how_long(self):
        text = self.announce()
        self.assertIn("waiting", text)
        self.assertIn("900", text)

    def test_it_names_the_challenge_it_is_waiting_on(self):
        self.assertIn("captcha-box", self.announce())


class TestTheMessage(unittest.TestCase):
    def report(self) -> str:
        challenge = driver_mod.BotChallenge(ARTICLE, "#captcha-box present")
        with mock.patch("sys.stderr", new_callable=_Capture) as err:
            kcl_fetch._report_challenge("openathens", DOI, challenge)
        return err.text

    def unanswered(self) -> str:
        challenge = driver_mod.BotChallenge(
            ARTICLE, "#captcha-box present", waited=900.0
        )
        with mock.patch("sys.stderr", new_callable=_Capture) as err:
            kcl_fetch._report_challenge("openathens", DOI, challenge)
        return err.text

    def test_the_advice_promises_a_window_that_waits(self):
        """The advice has to be an instruction that actually works."""
        text = self.report()
        self.assertIn(f"kcl-fetch get {DOI} --show", text)
        self.assertIn("waiting up to", text)
        self.assertIn("--timeout", text)

    def test_the_advice_names_the_screen_the_window_opens_on(self):
        self.assertIn(socket.gethostname(), self.report())

    def test_an_unanswered_challenge_is_reported_as_that_and_not_as_advice(self):
        text = self.unanswered()
        self.assertIn("not completed", text)
        self.assertIn("--timeout", text)
        self.assertNotIn("kcl-fetch get", text)

    def test_an_unanswered_challenge_is_still_not_a_subscription_gap(self):
        text = self.unanswered()
        self.assertIn("not a subscription gap", text)
        self.assertNotIn("may not hold", text)

    def test_it_names_the_publisher_and_the_challenge(self):
        text = self.report()
        self.assertIn("sciencedirect.com", text)
        self.assertIn("captcha-box", text)

    def test_it_says_the_library_is_the_wrong_place_to_go(self):
        text = self.report()
        self.assertIn("not a subscription gap", text)
        self.assertNotIn("may not hold", text)

    def test_it_hands_the_window_to_a_human_rather_than_solving_anything(self):
        text = self.report()
        self.assertIn("--show", text)
        self.assertIn(DOI, text)

    def test_it_says_why_the_second_route_is_not_tried(self):
        self.assertIn("second request", self.report())

    def test_it_mentions_the_exit_address(self):
        """A proxied exit IP is most of the signal, and is invisible from here."""
        self.assertIn("VPN or proxy", self.report())


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
