"""Crossref feeds the enumeration detector, and must never block a fetch."""

from __future__ import annotations

import io
import json
import unittest
import urllib.error

from kcl_fetch_lib import metadata

WORK = {
    "message": {
        "container-title": ["Journal of Tests"],
        "volume": "12",
        "issue": "4",
        "resource": {"primary": {"URL": "https://www.sciencedirect.com/pii/S1"}},
    }
}


class _Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False


def responder(payload, capture: list | None = None):
    def opener(request, timeout=None):
        if capture is not None:
            capture.append(request)
        return _Response(json.dumps(payload).encode())

    return opener


class TestLookup(unittest.TestCase):
    def test_issue_metadata_and_landing_url_are_extracted(self):
        record = metadata.lookup("10.1000/abc", opener=responder(WORK))
        self.assertEqual(record.meta.journal, "Journal of Tests")
        self.assertEqual(record.meta.volume, "12")
        self.assertEqual(record.meta.issue, "4")
        self.assertEqual(record.landing_url, "https://www.sciencedirect.com/pii/S1")

    def test_a_failure_yields_an_empty_record_rather_than_raising(self):
        for failure in (urllib.error.URLError("down"), ValueError("junk"), OSError()):
            def opener(_request, timeout=None, failure=failure):
                raise failure

            with self.subTest(failure=type(failure).__name__):
                record = metadata.lookup("10.1000/abc", opener=opener)
                self.assertIsNone(record.meta.issue_key())
                self.assertIsNone(record.landing_url)

    def test_a_work_with_no_issue_gives_no_issue_key(self):
        record = metadata.lookup(
            "10.1000/abc", opener=responder({"message": {"volume": "12"}})
        )
        self.assertIsNone(record.meta.issue_key())


class TestContactIsOptOut(unittest.TestCase):
    """An address is personal data; it is only sent when explicitly supplied."""

    def test_no_contact_is_configured_by_default(self):
        self.assertEqual(metadata.user_agent(env={}), "kcl-fetch/0.1")
        self.assertNotIn("mailto", metadata.user_agent(env={}))

    def test_a_supplied_contact_joins_the_polite_pool(self):
        self.assertEqual(
            metadata.user_agent(env={metadata.CONTACT_ENV: "me@example.org"}),
            "kcl-fetch/0.1 (mailto:me@example.org)",
        )

    def test_no_address_is_baked_into_the_source(self):
        from pathlib import Path

        source = Path(metadata.__file__).read_text(encoding="utf-8")
        self.assertNotIn("@yandex", source)
        self.assertNotIn("mailto:l", source)


if __name__ == "__main__":
    unittest.main()
