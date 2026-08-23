"""The routing table is a prior that corrects itself, not a fact table."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from kcl_fetch_lib.routing import RoutingTable
from kcl_fetch_lib.urls import EZPROXY, OPENATHENS


class TestRouting(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.path = Path(self._tmp.name) / "routes.json"
        self.addCleanup(self._tmp.cleanup)

    def table(self) -> RoutingTable:
        return RoutingTable(self.path)

    def test_openathens_is_the_default_for_an_unseen_host(self):
        self.assertEqual(self.table().preferred("obscure-press.example"), OPENATHENS)

    def test_a_seeded_host_prefers_openathens(self):
        self.assertEqual(self.table().preferred("sciencedirect.com"), OPENATHENS)

    def test_subdomains_inherit_from_the_parent_domain(self):
        table = self.table()
        table.record("example-press.com", EZPROXY, worked=True)
        self.assertEqual(table.preferred("journals.example-press.com"), EZPROXY)

    def test_both_templates_are_offered_preferred_first(self):
        table = self.table()
        self.assertEqual(table.order("nature.com"), [OPENATHENS, EZPROXY])
        table.record("nature.com", EZPROXY, worked=True)
        self.assertEqual(table.order("nature.com"), [EZPROXY, OPENATHENS])

    def test_order_never_offers_more_than_the_two_real_templates(self):
        self.assertEqual(len(self.table().order("anything.example")), 2)

    def test_a_failure_flips_the_host_to_the_other_template(self):
        table = self.table()
        table.record("nature.com", OPENATHENS, worked=False)
        self.assertEqual(table.preferred("nature.com"), EZPROXY)

    def test_learning_survives_a_restart(self):
        self.table().record("nature.com", EZPROXY, worked=True)
        self.assertEqual(self.table().preferred("nature.com"), EZPROXY)

    def test_a_corrupt_cache_falls_back_to_the_seed_instead_of_raising(self):
        self.path.write_text("{not json", encoding="utf-8")
        self.assertEqual(self.table().preferred("sciencedirect.com"), OPENATHENS)

    def test_a_bogus_template_in_the_cache_is_ignored(self):
        self.path.write_text('{"hosts": {"nature.com": "carsi"}}', encoding="utf-8")
        self.assertEqual(self.table().preferred("nature.com"), OPENATHENS)

    def test_recording_a_bogus_template_changes_nothing(self):
        table = self.table()
        table.record("nature.com", "carsi", worked=True)
        self.assertEqual(table.preferred("nature.com"), OPENATHENS)


if __name__ == "__main__":
    unittest.main()
