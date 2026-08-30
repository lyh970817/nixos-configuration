"""An expired session is not a subscription gap.

The observed failure, on `10.1016/j.jad.2024.01.106`:

    kcl-fetch: openathens route failed -- no downloadable PDF on
    https://login.microsoftonline.com/8370cf14-.../saml2?SAMLRequest=... --
    KCL may not hold this article, or the link is behind a purchase option

The browser ended on Microsoft Entra's sign-in page and never reached the
publisher, and the tool answered with a verdict about KCL's holdings. That
sends the user to the library over a lapsed cookie.

Why the existing check missed it: an SSO hop is a JavaScript auto-POST, not an
HTTP redirect, so `goto(wait_until="domcontentloaded")` returns on the form
several hops before Entra. The login wall only exists after the chain has run
-- which is why the URL in the message above *is* the Entra one, printed by the
code path that had already decided this was an entitlement problem.
"""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import kcl_fetch
from kcl_fetch_lib import driver as driver_mod
from kcl_fetch_lib import gate as gate_mod
from kcl_fetch_lib import remote
from support import GateFixture

ENTRA = (
    "https://login.microsoftonline.com/8370cf14-0000-0000-0000-000000000000"
    "/saml2?SAMLRequest=fZJRb4IwFIX%2FCuk7tIBOaZTEaZaZuI2I28NelkovroktrC1u%2F35"
)
KCL_IDP = "https://kclidp.kcl.ac.uk/idp/profile/SAML2/Redirect/SSO?execution=e1s1"
OPENATHENS = "https://login.openathens.net/auth?entityID=kcl"
PUBLISHER = "https://www.sciencedirect.com/science/article/pii/S0165032724001101"


class FakePage:
    """Just enough Playwright page for the classification under test."""

    def __init__(self, url: str, *, body: str = "Abstract", ends_at: str | None = None):
        self.url = url
        self.body = body
        self._ends_at = ends_at
        self.settled = 0

    def goto(self, *_a, **_k):
        return None

    def wait_for_load_state(self, _state, timeout=None):
        # The SSO chain finishing is exactly what this stands for.
        self.settled += 1
        if self._ends_at is not None:
            self.url = self._ends_at
            self._ends_at = None

    def inner_text(self, _selector, timeout=None):
        return self.body


def browser_over(page: FakePage, *, lands_on: str | None = None):
    """A `Browser` whose page is `page` and whose download attempt finds nothing.

    `lands_on` is where the browser has drifted to by the time the download
    attempt gives up -- the late navigation that the original check could not
    see.
    """
    browser = driver_mod.Browser(
        profile_dir=Path(tempfile.mkdtemp()),
        chromium="/nonexistent/chromium",
        downloads_dir=Path(tempfile.mkdtemp()),
    )
    browser.page = lambda: page

    def no_download(target):
        if lands_on is not None:
            target.url = lands_on
        return None

    browser._trigger_download = no_download
    return browser


def fetch(browser):
    return browser.fetch_pdf(
        "https://go.openathens.net/redirector/kcl.ac.uk?url=x",
        doi="10.1016/j.jad.2024.01.106",
        template="openathens",
        out_dir=Path(tempfile.mkdtemp()),
        stem="doi",
        min_bytes=1000,
    )


class TestLoginHostClassification(unittest.TestCase):
    def test_the_three_walls_are_recognised(self):
        for url in (ENTRA, KCL_IDP, OPENATHENS):
            with self.subTest(url=url):
                self.assertTrue(driver_mod.is_login_host(url))

    def test_a_publisher_is_not_a_wall(self):
        self.assertFalse(driver_mod.is_login_host(PUBLISHER))
        self.assertFalse(driver_mod.is_login_host("https://onlinelibrary.wiley.com/x"))

    def test_subdomains_of_a_known_wall_count(self):
        """Entra serves prompts and assets from `*.msftauth.net`."""
        self.assertTrue(driver_mod.is_login_host("https://aadcdn.msftauth.net/x"))
        self.assertTrue(driver_mod.is_login_host("https://a.login.openathens.net/x"))

    def test_a_lookalike_domain_is_not_a_wall(self):
        """Suffix matching must be on labels, not on characters."""
        self.assertFalse(
            driver_mod.is_login_host("https://notlogin.openathens.net.example.com/x")
        )

    def test_a_url_with_no_host_is_not_a_wall(self):
        self.assertFalse(driver_mod.is_login_host("about:blank"))


class TestTheReproducedBug(unittest.TestCase):
    def test_a_late_arrival_at_entra_is_a_login_wall_not_a_holdings_verdict(self):
        page = FakePage(PUBLISHER)
        with self.assertRaises(driver_mod.LoginRequired) as caught:
            fetch(browser_over(page, lands_on=ENTRA))
        message = str(caught.exception)
        self.assertIn("sign-in wall", message)
        self.assertIn("login.microsoftonline.com", message)
        self.assertNotIn("may not hold", message)

    def test_the_same_holds_for_the_kcl_idp_and_for_openathens(self):
        for wall in (KCL_IDP, OPENATHENS):
            with self.subTest(wall=wall):
                page = FakePage(PUBLISHER)
                with self.assertRaises(driver_mod.LoginRequired):
                    fetch(browser_over(page, lands_on=wall))

    def test_the_chain_is_settled_before_the_first_verdict(self):
        """`domcontentloaded` returns mid-chain; reading the URL there is a guess."""
        page = FakePage("https://go.openathens.net/redirector/kcl.ac.uk",
                        ends_at=ENTRA)
        with self.assertRaises(driver_mod.LoginRequired):
            fetch(browser_over(page))
        self.assertEqual(page.settled, 1)

    def test_reaching_the_publisher_with_a_purchase_offer_is_a_holdings_answer(self):
        """The distinction has to cut both ways or it is just a louder message.

        What counts as the other way has since been narrowed: the offer to
        sell us the article, not merely the absence of a link (see
        `test_bot_challenge.TestTheEntitlementVerdictIsNarrowed`).
        """
        page = FakePage(PUBLISHER, body="Get Access to the full text")
        with self.assertRaises(driver_mod.NoFullText) as caught:
            fetch(browser_over(page))
        message = str(caught.exception)
        self.assertIn("sciencedirect.com", message)
        self.assertIn("does not appear to cover", message)
        self.assertNotIn("sign-in wall", message)

    def test_an_immediate_wall_is_still_caught_before_any_clicking(self):
        page = FakePage(ENTRA)
        browser = browser_over(page)
        browser._trigger_download = lambda _p: self.fail("clicked past a login wall")
        with self.assertRaises(driver_mod.LoginRequired):
            fetch(browser)


class TestTheMessage(unittest.TestCase):
    def report(self, url: str, environ=None):
        needed = driver_mod.LoginRequired(url)
        with mock.patch.object(
            remote, "login_command", return_value="kcl-fetch login"
        ):
            with mock.patch("sys.stderr", new_callable=_Capture) as err:
                kcl_fetch._report_login_wall("openathens", needed)
        return err.text

    def test_it_names_the_wall_and_the_command_that_clears_it(self):
        text = self.report(ENTRA)
        self.assertIn("login.microsoftonline.com", text)
        self.assertIn("`kcl-fetch login`", text)

    def test_it_says_the_library_is_the_wrong_place_to_go(self):
        text = self.report(ENTRA)
        self.assertIn("not a subscription gap", text)
        self.assertNotIn("may not hold", text)
        self.assertNotIn("scansci-oa", text)

    def test_it_terminates_rather_than_offering_a_window(self):
        """`get` runs on a virtual display: it has no window to hand over."""
        text = self.report(ENTRA)
        self.assertNotIn("window that opens", text)
        self.assertNotIn("waiting", text)

    def test_it_says_the_attempt_was_free(self):
        self.assertIn("No budget was spent", self.report(ENTRA))


class TestWhichLoginToSuggest(unittest.TestCase):
    def test_locally_it_is_the_plain_command(self):
        self.assertEqual(remote.login_command({}), "kcl-fetch login")

    def test_over_ssh_it_carries_on_so_the_window_opens_where_the_user_is(self):
        self.assertEqual(
            remote.login_command(
                {"SSH_CONNECTION": "10.0.0.2 5 10.0.0.1 22",
                 remote.PEER_HOST_ENV: "dynabook"}
            ),
            "kcl-fetch login --on dynabook",
        )

    def test_over_ssh_with_no_peer_it_asks_for_a_host(self):
        self.assertEqual(
            remote.login_command({"SSH_CONNECTION": "10.0.0.2 5 10.0.0.1 22"}),
            "kcl-fetch login --on HOST",
        )


REDIRECTOR = "https://go.openathens.net/redirector/kcl.ac.uk?url=x"
PORTAL = "https://my.openathens.net/"


class ScriptedPage(FakePage):
    """A page that walks a fixed list of URLs, one poll at a time."""

    def __init__(self, steps: list[str]):
        super().__init__(steps[0])
        self.steps = list(steps)
        self.waited = 0

    def wait_for_load_state(self, _state, timeout=None):
        self.settled += 1

    def wait_for_timeout(self, _ms):
        self.waited += 1
        if len(self.steps) > 1:
            self.steps.pop(0)
            self.url = self.steps[0]

    def inner_text(self, _selector, timeout=None):
        return "Abstract"


class TestWhenLoginIsFinished(unittest.TestCase):
    """The `login` that reported success and established nothing."""

    def login(self, steps: list[str], **kwargs) -> bool:
        page = ScriptedPage(steps)
        browser = browser_over(page)
        self.page = page
        return browser.interactive_login(
            REDIRECTOR,
            wait_seconds=kwargs.pop("wait_seconds", 60.0),
            target_host=kwargs.pop("target_host", "my.openathens.net"),
        )

    def test_sitting_on_the_redirector_is_not_being_signed_in(self):
        """The regression: neither the redirector nor a wall, so the old test
        said "done" before a single hop had run."""
        self.assertFalse(driver_mod.is_login_host(REDIRECTOR))
        self.assertFalse(self.login([REDIRECTOR], wait_seconds=0.0))

    def test_arriving_at_the_target_is(self):
        self.assertTrue(self.login([REDIRECTOR, OPENATHENS, ENTRA, PORTAL]))

    def test_a_subpage_of_the_target_counts(self):
        self.assertTrue(
            self.login([REDIRECTOR, ENTRA, "https://my.openathens.net/dashboard"])
        )

    def test_it_waits_through_the_whole_wall(self):
        page_steps = [REDIRECTOR, OPENATHENS, ENTRA, ENTRA, ENTRA, PORTAL]
        self.assertTrue(self.login(page_steps))
        # One poll per step, so the human was never hurried past the prompt.
        self.assertGreaterEqual(self.page.waited, 4)

    def test_landing_somewhere_else_after_a_wall_is_accepted(self):
        """A federation that ends at the SP rather than the portal still worked."""
        self.assertTrue(self.login([REDIRECTOR, ENTRA, PUBLISHER]))

    def test_a_wall_that_never_clears_times_out(self):
        self.assertFalse(self.login([ENTRA], wait_seconds=0.0))

    def test_the_chain_is_settled_before_each_verdict(self):
        self.login([REDIRECTOR, ENTRA, PORTAL])
        self.assertGreaterEqual(self.page.settled, 3)


class TestGateAccounting(unittest.TestCase):
    """An auth lapse must not bill the institutional budget."""

    def setUp(self) -> None:
        self.fixture = GateFixture()
        self.addCleanup(self.fixture.close)

    def test_a_login_wall_spends_no_budget(self):
        before = self.fixture.gate.budget_state()["short"][0]
        with self.fixture.gate.acquire("sciencedirect.com", "10.1/x") as attempt:
            attempt.login_wall("stopped at login.microsoftonline.com")
        self.assertEqual(self.fixture.gate.budget_state()["short"][0], before)

    def test_a_real_miss_still_does(self):
        with self.fixture.gate.acquire("sciencedirect.com", "10.1/x") as attempt:
            attempt.miss("no PDF")
        self.assertEqual(self.fixture.gate.budget_state()["short"][0], 1)

    def test_it_is_still_written_to_the_ledger(self):
        with self.fixture.gate.acquire("sciencedirect.com", "10.1/x") as attempt:
            attempt.login_wall("stopped at login.microsoftonline.com")
        row = self.fixture.gate.recent(1)[0]
        self.assertEqual(row["outcome"], gate_mod.LOGIN_WALL_OUTCOME)
        self.assertIn("login.microsoftonline.com", row["detail"])

    def test_the_outcome_is_deliberately_outside_the_spending_set(self):
        self.assertNotIn(gate_mod.LOGIN_WALL_OUTCOME, gate_mod.SPENDING_OUTCOMES)

    def test_a_spent_budget_does_not_hide_behind_an_auth_failure(self):
        """Ten walls in a row leave the budget exactly where it started."""
        # Unrelated DOIs: a consecutive run would be refused as enumeration
        # before the wall could be reached.
        for journal in "abcdefghij":
            with self.fixture.gate.acquire("sciencedirect.com", f"10.1/{journal}") as a:
                a.login_wall("wall")
        self.assertEqual(self.fixture.gate.budget_state()["long"][0], 0)


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
