"""LibKey is an optimisation, so every way it can fail must be a no-op.

The user has no key. If any of these paths raised or returned "no full text",
an unconfigured install would refuse to fetch anything at all.
"""

from __future__ import annotations

import io
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path

from kcl_fetch_lib import libkey

CREDS = libkey.LibKeyCredentials("1234", "tok-secret")


class _Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False


def responder(payload, capture: list | None = None):
    def opener(request, timeout=None):
        if capture is not None:
            capture.append(request.full_url)
        return _Response(json.dumps(payload).encode())

    return opener


class TestUnconfiguredIsANoOp(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_no_env_and_no_file_means_no_credentials(self):
        self.assertIsNone(
            libkey.load_credentials(env={}, key_file=self.root / "absent")
        )

    def test_precheck_returns_none_rather_than_raising(self):
        def explode(*_a, **_k):  # pragma: no cover - must never be reached
            raise AssertionError("precheck called the API without credentials")

        self.assertIsNone(
            libkey.precheck("10.1000/abc", credentials=None, opener=explode)
        )

    def test_a_half_configured_environment_is_still_unconfigured(self):
        self.assertIsNone(
            libkey.load_credentials(
                env={libkey.ENV_TOKEN: "tok"}, key_file=self.root / "absent"
            )
        )
        self.assertIsNone(
            libkey.load_credentials(
                env={libkey.ENV_LIBRARY: "1234"}, key_file=self.root / "absent"
            )
        )

    def test_an_empty_or_unparseable_key_file_is_unconfigured(self):
        for body in ("", "{not json", "{}", '{"token": ""}'):
            path = self.root / "libkey"
            path.write_text(body, encoding="utf-8")
            path.chmod(0o600)
            with self.subTest(body=body):
                self.assertIsNone(libkey.load_credentials(env={}, key_file=path))


class TestCredentialLoading(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_the_environment_wins(self):
        creds = libkey.load_credentials(
            env={libkey.ENV_TOKEN: "tok", libkey.ENV_LIBRARY: "99"},
            key_file=self.root / "absent",
        )
        self.assertEqual(creds, libkey.LibKeyCredentials("99", "tok"))

    def test_a_0600_file_is_read(self):
        path = self.root / "libkey"
        path.write_text(json.dumps({"library_id": "99", "token": "tok"}), encoding="utf-8")
        path.chmod(0o600)
        self.assertEqual(
            libkey.load_credentials(env={}, key_file=path),
            libkey.LibKeyCredentials("99", "tok"),
        )

    def test_a_world_readable_key_file_is_an_error_not_a_warning(self):
        path = self.root / "libkey"
        path.write_text(json.dumps({"library_id": "99", "token": "tok"}), encoding="utf-8")
        path.chmod(0o644)
        with self.assertRaises(PermissionError):
            libkey.load_credentials(env={}, key_file=path)


class TestPrecheck(unittest.TestCase):
    def test_full_text_and_metadata_are_extracted(self):
        payload = {
            "data": {
                "fullTextFile": "https://pub.example/full.pdf",
                "contentLocation": "https://pub.example/article",
                "volume": 12,
                "issue": 4,
            },
            "included": [{"type": "journals", "title": "Journal of Tests"}],
        }
        result = libkey.precheck(
            "10.1000/abc", credentials=CREDS, opener=responder(payload)
        )
        self.assertTrue(result.full_text)
        self.assertEqual(result.pdf_url, "https://pub.example/full.pdf")
        self.assertEqual(result.meta.journal, "Journal of Tests")
        self.assertEqual(result.meta.volume, "12")
        self.assertEqual(result.meta.issue, "4")
        self.assertFalse(result.retracted)

    def test_no_holding_reports_no_full_text(self):
        result = libkey.precheck(
            "10.1000/abc", credentials=CREDS, opener=responder({"data": {}})
        )
        self.assertFalse(result.full_text)

    def test_a_retraction_notice_is_surfaced(self):
        payload = {
            "data": {
                "fullTextFile": "https://pub.example/full.pdf",
                "retractionNoticeUrl": "https://pub.example/retracted",
            }
        }
        result = libkey.precheck(
            "10.1000/abc", credentials=CREDS, opener=responder(payload)
        )
        self.assertTrue(result.retracted)

    def test_network_and_parse_failures_degrade_to_none(self):
        for failure in (
            urllib.error.URLError("down"),
            TimeoutError("slow"),
            ValueError("garbage"),
            OSError("refused"),
        ):
            def opener(_request, timeout=None, failure=failure):
                raise failure

            with self.subTest(failure=type(failure).__name__):
                self.assertIsNone(
                    libkey.precheck("10.1000/abc", credentials=CREDS, opener=opener)
                )

    def test_the_doi_slash_stays_structural_in_the_api_path(self):
        seen: list[str] = []
        libkey.precheck(
            "10.1000/abc", credentials=CREDS, opener=responder({"data": {}}, seen)
        )
        self.assertIn("/articles/doi/10.1000/abc?", seen[0])

    def test_redaction_hides_the_token(self):
        seen: list[str] = []
        libkey.precheck(
            "10.1000/abc", credentials=CREDS, opener=responder({"data": {}}, seen)
        )
        self.assertIn("tok-secret", seen[0])
        self.assertNotIn("tok-secret", libkey.redact(seen[0]))


if __name__ == "__main__":
    unittest.main()
