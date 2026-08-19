"""Ordered mirror resolution, failover, and caching."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from annas_books_lib import mirrors  # noqa: E402

BASES = ("https://a.example", "https://b.example", "https://c.example")


def probe_only(*alive):
    """A probe that answers for the named bases and records what it tried."""
    tried = []

    def probe(base):
        tried.append(base)
        return base in alive

    probe.tried = tried
    return probe


class ResolveTests(unittest.TestCase):
    def test_first_live_base_wins(self):
        probe = probe_only(*BASES)
        self.assertEqual(mirrors.resolve_base(probe, bases=BASES), BASES[0])
        self.assertEqual(probe.tried, [BASES[0]])

    def test_fails_over_past_dead_mirrors(self):
        probe = probe_only(BASES[2])
        self.assertEqual(mirrors.resolve_base(probe, bases=BASES), BASES[2])
        self.assertEqual(probe.tried, list(BASES))

    def test_raises_when_nothing_answers(self):
        probe = probe_only()
        with self.assertRaises(mirrors.NoMirrorError) as ctx:
            mirrors.resolve_base(probe, bases=BASES)
        self.assertIn("no Anna's Archive mirror answered", str(ctx.exception))

    def test_default_bases_are_ordered_by_measured_reliability(self):
        self.assertEqual(mirrors.DEFAULT_BASES[0], "https://annas-archive.gd")
        self.assertEqual(mirrors.DEFAULT_BASES[1], "https://annas-archive.gl")


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name) / "mirror.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_first_success_is_cached(self):
        probe = probe_only(BASES[1])
        mirrors.resolve_base(probe, bases=BASES, cache_path=self.cache, now=1000.0)
        self.assertEqual(json.loads(self.cache.read_text())["base"], BASES[1])

    def test_cached_base_is_tried_first(self):
        mirrors.write_cache(self.cache, BASES[2], now=1000.0)
        probe = probe_only(*BASES)
        got = mirrors.resolve_base(
            probe, bases=BASES, cache_path=self.cache, now=1000.0
        )
        self.assertEqual(got, BASES[2])
        self.assertEqual(probe.tried, [BASES[2]])

    def test_cached_base_that_died_falls_back(self):
        mirrors.write_cache(self.cache, BASES[2], now=1000.0)
        probe = probe_only(BASES[0])
        got = mirrors.resolve_base(
            probe, bases=BASES, cache_path=self.cache, now=1000.0
        )
        self.assertEqual(got, BASES[0])
        self.assertEqual(probe.tried[0], BASES[2])
        self.assertEqual(json.loads(self.cache.read_text())["base"], BASES[0])

    def test_stale_cache_is_ignored(self):
        mirrors.write_cache(self.cache, BASES[2], now=0.0)
        probe = probe_only(*BASES)
        got = mirrors.resolve_base(
            probe, bases=BASES, cache_path=self.cache, ttl=10.0, now=1000.0
        )
        self.assertEqual(got, BASES[0])

    def test_corrupt_cache_is_ignored(self):
        self.cache.write_text("not json")
        probe = probe_only(*BASES)
        self.assertEqual(
            mirrors.resolve_base(probe, bases=BASES, cache_path=self.cache), BASES[0]
        )

    def test_missing_cache_is_not_an_error(self):
        self.assertIsNone(mirrors.read_cache(self.cache))


if __name__ == "__main__":
    unittest.main()
