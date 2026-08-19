"""Key loading rules and redaction of the key from anything printed."""

import sys
import tempfile
import unittest
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from annas_books_lib import secrets  # noqa: E402

KEY = "s3cr3t-membership-key/with+chars"


class LoadKeyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "secret-key"

    def tearDown(self):
        self.tmp.cleanup()

    def _write(self, text, mode=0o600):
        self.path.write_text(text)
        self.path.chmod(mode)

    def test_env_wins(self):
        self._write("from-file")
        got = secrets.load_key(env={secrets.ENV_VAR: "from-env"}, key_file=self.path)
        self.assertEqual(got, "from-env")

    def test_env_is_stripped(self):
        got = secrets.load_key(env={secrets.ENV_VAR: "  k  "}, key_file=self.path)
        self.assertEqual(got, "k")

    def test_file_is_read_when_env_is_unset(self):
        self._write("from-file\n")
        self.assertEqual(secrets.load_key(env={}, key_file=self.path), "from-file")

    def test_empty_env_falls_through_to_file(self):
        self._write("from-file")
        got = secrets.load_key(env={secrets.ENV_VAR: ""}, key_file=self.path)
        self.assertEqual(got, "from-file")

    def test_group_readable_file_is_refused(self):
        self._write("from-file", mode=0o640)
        with self.assertRaises(secrets.MissingKeyError) as ctx:
            secrets.load_key(env={}, key_file=self.path)
        self.assertIn("chmod 600", str(ctx.exception))

    def test_world_readable_file_is_refused(self):
        self._write("from-file", mode=0o604)
        with self.assertRaises(secrets.MissingKeyError):
            secrets.load_key(env={}, key_file=self.path)

    def test_missing_file_is_reported_with_both_options(self):
        with self.assertRaises(secrets.MissingKeyError) as ctx:
            secrets.load_key(env={}, key_file=self.path)
        self.assertIn(secrets.ENV_VAR, str(ctx.exception))
        self.assertIn(str(self.path), str(ctx.exception))

    def test_empty_file_is_refused(self):
        self._write("   \n")
        with self.assertRaises(secrets.MissingKeyError):
            secrets.load_key(env={}, key_file=self.path)


class RedactTests(unittest.TestCase):
    def test_literal_key_is_masked(self):
        out = secrets.redact(f"GET /dyn/api/fast_download.json?md5=abc&key={KEY}", KEY)
        self.assertNotIn(KEY, out)
        self.assertIn(secrets.REDACTED, out)

    def test_percent_encoded_key_is_masked(self):
        quoted = urllib.parse.quote(KEY, safe="")
        out = secrets.redact(f"https://x/api?key={quoted}", KEY)
        self.assertNotIn(quoted, out)
        self.assertNotIn(KEY, out)

    def test_key_parameter_is_masked_even_without_the_key(self):
        out = secrets.redact("https://x/api?md5=abc&key=some-other-secret")
        self.assertNotIn("some-other-secret", out)
        self.assertIn("md5=abc", out)

    def test_key_parameter_masking_stops_at_the_ampersand(self):
        out = secrets.redact("?key=abc123&md5=deadbeef")
        self.assertIn("md5=deadbeef", out)
        self.assertNotIn("abc123", out)

    def test_multiple_occurrences_are_all_masked(self):
        out = secrets.redact(f"{KEY} ... {KEY}", KEY)
        self.assertNotIn(KEY, out)
        self.assertEqual(out.count(secrets.REDACTED), 2)

    def test_non_string_input(self):
        self.assertEqual(secrets.redact(42, KEY), "42")

    def test_text_without_the_key_is_untouched(self):
        self.assertEqual(secrets.redact("nothing to see", KEY), "nothing to see")

    def test_client_errors_are_scrubbed(self):
        from annas_books_lib.client import AnnasClient

        client = AnnasClient(key=KEY, state_dir=Path(tempfile.mkdtemp()))
        msg = client.scrub(f"failed: https://x/api?md5=abc&key={KEY}")
        self.assertNotIn(KEY, msg)


if __name__ == "__main__":
    unittest.main()
