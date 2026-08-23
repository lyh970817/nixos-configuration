"""The gate is the component where a bug has consequences outside this machine.

A publisher block lands on KCL's whole IP range and an EZproxy `UsageLimit`
trip needs a library administrator to clear it, so every rule here is tested
for the refusal, not just for the happy path. Nothing sleeps: the clock is
injected, so a rolling-window test costs microseconds rather than three hours.
"""

from __future__ import annotations

import unittest

from kcl_fetch_lib.gate import (
    ArticleMeta,
    BudgetExhausted,
    ConcurrencyRefused,
    EnumerationSuspected,
    PublisherBlocked,
    _has_sequential_run,
)
from kcl_fetch_lib.limits import DEFAULTS, Limits, LimitsConfigError

from support import GateFixture


def spaced_doi(n: int) -> str:
    """A DOI that cannot be read as part of a consecutive run."""
    return f"10.1000/x{n * 100}"


class GateTestCase(unittest.TestCase):
    limits = DEFAULTS

    def setUp(self) -> None:
        self.fx = GateFixture(self.limits)
        self.gate = self.fx.gate
        self.clock = self.fx.clock
        self.addCleanup(self.fx.close)


class TestRateLimiting(GateTestCase):
    def test_global_spacing_is_at_least_one_second(self):
        self.fx.fetch("a.example", spaced_doi(1))
        start = self.clock.now()
        self.fx.fetch("b.example", spaced_doi(2))
        self.assertGreaterEqual(self.clock.now() - start, 1.0)

    def test_same_host_waits_the_full_cooldown(self):
        self.fx.fetch("sciencedirect.com", spaced_doi(1))
        start = self.clock.now()
        self.fx.fetch("sciencedirect.com", spaced_doi(2))
        self.assertGreaterEqual(
            self.clock.now() - start, DEFAULTS.host_cooldown
        )

    def test_cooldown_is_per_host_not_global(self):
        self.fx.fetch("sciencedirect.com", spaced_doi(1))
        start = self.clock.now()
        self.fx.fetch("nature.com", spaced_doi(2))
        elapsed = self.clock.now() - start
        self.assertGreaterEqual(elapsed, DEFAULTS.global_min_interval)
        self.assertLess(elapsed, DEFAULTS.host_cooldown)

    def test_no_wait_when_the_host_has_already_cooled_down(self):
        self.fx.fetch("sciencedirect.com", spaced_doi(1))
        self.clock.advance(3600)
        start = self.clock.now()
        self.fx.fetch("sciencedirect.com", spaced_doi(2))
        self.assertEqual(self.clock.now(), start)


class TestBudget(GateTestCase):
    def test_short_window_cap_refuses_the_next_fetch(self):
        for i in range(DEFAULTS.short_window_max):
            self.fx.fetch(f"h{i}.example", spaced_doi(i))
        with self.assertRaises(BudgetExhausted) as caught:
            self.gate.acquire("h99.example", spaced_doi(99))
        self.assertIn("3-hour", str(caught.exception))

    def test_budget_rolls_over_as_the_window_slides(self):
        for i in range(DEFAULTS.short_window_max):
            self.fx.fetch(f"h{i}.example", spaced_doi(i))
        with self.assertRaises(BudgetExhausted) as caught:
            self.gate.acquire("h99.example", spaced_doi(99))

        # Just short of the oldest attempt ageing out: still refused.
        self.clock.advance(caught.exception.retry_after - 1)
        with self.assertRaises(BudgetExhausted):
            self.gate.acquire("h99.example", spaced_doi(99))

        # Past it: the oldest attempt has left the window, one slot is free.
        self.clock.advance(2)
        self.fx.fetch("h99.example", spaced_doi(99))

    def test_daily_cap_still_bites_after_short_windows_have_rolled(self):
        limits = DEFAULTS.tighten({"long_window_max": 30})
        fx = GateFixture(limits)
        self.addCleanup(fx.close)
        for i in range(30):
            fx.fetch(f"h{i}.example", spaced_doi(i))
            fx.clock.advance(1800)  # half an hour apart: never trips 25/3h
        with self.assertRaises(BudgetExhausted) as caught:
            fx.gate.acquire("h99.example", spaced_doi(99))
        self.assertIn("daily", str(caught.exception))

    def test_refusals_do_not_spend_budget(self):
        for i in range(DEFAULTS.short_window_max):
            self.fx.fetch(f"h{i}.example", spaced_doi(i))
        for _ in range(5):
            with self.assertRaises(BudgetExhausted):
                self.gate.acquire("h99.example", spaced_doi(99))
        used, cap, _ = self.gate.budget_state()["short"]
        self.assertEqual(used, cap)

    def test_every_attempt_including_refusals_reaches_the_ledger(self):
        self.fx.fetch("a.example", spaced_doi(1))
        rows = self.gate.recent(10)
        self.assertEqual(rows[0]["outcome"], "ok")
        self.assertEqual(rows[0]["host"], "a.example")
        self.assertEqual(rows[0]["doi"], spaced_doi(1))
        self.assertIsNotNone(rows[0]["ts"])


class TestConcurrency(GateTestCase):
    def test_a_second_holder_is_refused_not_queued(self):
        other = self.fx.second_gate()
        self.addCleanup(other.close)
        attempt = self.gate.acquire("a.example", spaced_doi(1))
        with self.assertRaises(ConcurrencyRefused):
            other.acquire("b.example", spaced_doi(2))
        attempt.ok()

    def test_the_lock_is_released_when_the_attempt_finishes(self):
        other = self.fx.second_gate()
        self.addCleanup(other.close)
        with self.gate.acquire("a.example", spaced_doi(1)) as attempt:
            attempt.ok()
        other.acquire("b.example", spaced_doi(2)).ok()

    def test_the_lock_is_released_when_a_refusal_is_raised(self):
        other = self.fx.second_gate()
        self.addCleanup(other.close)
        self.gate.db.execute(
            "INSERT INTO blocks (host, ts, doi, status) VALUES (?, ?, ?, ?)",
            ("blocked.example", self.clock.now(), "10.1/x", 403),
        )
        with self.assertRaises(PublisherBlocked):
            self.gate.acquire("blocked.example", spaced_doi(1))
        other.acquire("b.example", spaced_doi(2)).ok()


class TestEnumerationDetector(GateTestCase):
    def issue(self, journal="Journal of Tests", volume="12", issue="4"):
        return ArticleMeta(journal, volume, issue)

    def test_three_dois_from_one_issue_are_refused(self):
        self.fx.fetch("pub.example", "10.1000/aaa", self.issue())
        self.fx.fetch("pub.example", "10.1000/bbb", self.issue())
        with self.assertRaises(EnumerationSuspected) as caught:
            self.gate.acquire("pub.example", "10.1000/ccc", self.issue())
        self.assertIn("issue 4", str(caught.exception))

    def test_two_from_an_issue_is_reading_not_enumeration(self):
        self.fx.fetch("pub.example", "10.1000/aaa", self.issue())
        self.fx.fetch("pub.example", "10.1000/bbb", self.issue())
        self.fx.fetch("pub.example", "10.1000/zzz", self.issue(issue="9"))

    def test_the_issue_key_matches_case_insensitively(self):
        self.fx.fetch("pub.example", "10.1000/aaa", self.issue("Journal Of Tests"))
        self.fx.fetch("pub.example", "10.1000/bbb", self.issue("journal of tests "))
        with self.assertRaises(EnumerationSuspected):
            self.gate.acquire("pub.example", "10.1000/ccc", self.issue())

    def test_one_issue_slot_is_not_filled_by_repeats_of_one_doi(self):
        self.fx.fetch("pub.example", "10.1000/aaa", self.issue())
        self.fx.fetch("pub.example", "10.1000/aaa", self.issue(), outcome="miss")
        self.fx.fetch("pub.example", "10.1000/bbb", self.issue())

    def test_sequential_doi_suffixes_are_refused_without_any_metadata(self):
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.017")
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.018")
        with self.assertRaises(EnumerationSuspected) as caught:
            self.gate.acquire("pub.example", "10.1016/j.cell.2023.04.019")
        self.assertIn("range walking", str(caught.exception))

    def test_a_one_gap_run_still_counts_as_walking(self):
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.017")
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.019")
        with self.assertRaises(EnumerationSuspected):
            self.gate.acquire("pub.example", "10.1016/j.cell.2023.04.021")

    def test_scattered_dois_under_one_prefix_are_fine(self):
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.017")
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.140")
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.902")

    def test_different_stems_never_form_a_run(self):
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.017")
        self.fx.fetch("pub.example", "10.1038/s41586-023-00018")
        self.fx.fetch("pub.example", "10.1111/nph.19")

    def test_the_detector_forgets_once_the_window_has_passed(self):
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.017")
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.018")
        self.clock.advance(DEFAULTS.enumeration_window_seconds + 1)
        self.fx.fetch("pub.example", "10.1016/j.cell.2023.04.019")

    def test_run_helper(self):
        self.assertTrue(_has_sequential_run([5, 6, 7], 3))
        self.assertTrue(_has_sequential_run([5, 7, 9], 3))
        self.assertFalse(_has_sequential_run([5, 6], 3))
        self.assertFalse(_has_sequential_run([5, 6, 20], 3))
        self.assertFalse(_has_sequential_run([5, 5, 5], 3))


class TestBlocking(GateTestCase):
    def test_a_403_latches_the_host_off_permanently(self):
        with self.gate.acquire("pub.example", spaced_doi(1)) as attempt:
            with self.assertRaises(PublisherBlocked):
                attempt.blocked(403, "Forbidden")

        self.clock.advance(30 * 24 * 3600)
        with self.assertRaises(PublisherBlocked) as caught:
            self.gate.acquire("pub.example", spaced_doi(2))
        self.assertIn("library", caught.exception.advice())

    def test_a_block_on_one_host_does_not_stop_another(self):
        with self.gate.acquire("pub.example", spaced_doi(1)) as attempt:
            with self.assertRaises(PublisherBlocked):
                attempt.blocked(403)
        self.fx.fetch("other.example", spaced_doi(2))

    def test_the_block_is_recorded_with_its_status(self):
        with self.gate.acquire("pub.example", spaced_doi(1)) as attempt:
            with self.assertRaises(PublisherBlocked):
                attempt.blocked(403, "Forbidden")
        row = self.gate.block_record("pub.example")
        self.assertEqual(row["status"], 403)
        self.assertEqual(row["doi"], spaced_doi(1))


class TestLimitsAreOneWay(unittest.TestCase):
    """Configuration may only ever make this tool more cautious."""

    def test_caps_cannot_be_raised(self):
        for name, value in (
            ("short_window_max", DEFAULTS.short_window_max + 1),
            ("long_window_max", DEFAULTS.long_window_max + 1),
            ("enumeration_issue_threshold", DEFAULTS.enumeration_issue_threshold + 1),
            ("enumeration_sequential_threshold", 4),
            ("min_pdf_bytes", DEFAULTS.min_pdf_bytes + 1),
        ):
            with self.subTest(name=name):
                with self.assertRaises(LimitsConfigError):
                    DEFAULTS.tighten({name: value})

    def test_waits_and_windows_cannot_be_shortened(self):
        for name, value in (
            ("global_min_interval", 0.1),
            ("host_cooldown", 1.0),
            ("short_window_seconds", 60),
            ("long_window_seconds", 3600),
            ("enumeration_window_seconds", 600),
        ):
            with self.subTest(name=name):
                with self.assertRaises(LimitsConfigError):
                    DEFAULTS.tighten({name: value})

    def test_tightening_in_the_safe_direction_is_accepted(self):
        tighter = DEFAULTS.tighten(
            {
                "short_window_max": 5,
                "host_cooldown": 30.0,
                "enumeration_issue_threshold": 2,
                "long_window_seconds": 48 * 3600,
            }
        )
        self.assertEqual(tighter.short_window_max, 5)
        self.assertEqual(tighter.host_cooldown, 30.0)
        self.assertEqual(tighter.enumeration_issue_threshold, 2)

    def test_a_tightened_limits_cannot_be_loosened_back_towards_the_default(self):
        tighter = DEFAULTS.tighten({"short_window_max": 5})
        with self.assertRaises(LimitsConfigError):
            tighter.tighten({"short_window_max": DEFAULTS.short_window_max})

    def test_unknown_limits_are_rejected_rather_than_ignored(self):
        with self.assertRaises(LimitsConfigError):
            DEFAULTS.tighten({"concurrency": 4})
        with self.assertRaises(LimitsConfigError):
            DEFAULTS.tighten({"max_parallel": 8})

    def test_a_tightened_cap_actually_binds_at_runtime(self):
        fx = GateFixture(DEFAULTS.tighten({"short_window_max": 2}))
        self.addCleanup(fx.close)
        fx.fetch("a.example", spaced_doi(1))
        fx.fetch("b.example", spaced_doi(2))
        with self.assertRaises(BudgetExhausted):
            fx.gate.acquire("c.example", spaced_doi(3))

    def test_no_limits_field_names_concurrency(self):
        self.assertNotIn(
            "concurrency", {f for f in Limits.__dataclass_fields__}
        )


class TestNoBatchEntryPoint(unittest.TestCase):
    """Batch retrieval is absent, not disabled."""

    def test_the_gate_exposes_no_plural_admission(self):
        import kcl_fetch_lib.gate as gate_module

        names = [n for n in dir(gate_module.Gate) if not n.startswith("_")]
        for forbidden in ("acquire_many", "acquire_all", "batch", "bulk"):
            self.assertNotIn(forbidden, names)

    def test_acquire_takes_exactly_one_doi(self):
        import inspect

        from kcl_fetch_lib.gate import Gate

        params = list(inspect.signature(Gate.acquire).parameters)
        self.assertEqual(params, ["self", "host", "doi", "meta"])


if __name__ == "__main__":
    unittest.main()
