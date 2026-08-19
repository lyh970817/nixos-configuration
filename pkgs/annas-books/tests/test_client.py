"""Client behaviour against fake responses: challenge fallback, error mapping."""

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from annas_books_lib import client as client_mod  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"
KEY = "test-membership-key"


class FakeResponse:
    def __init__(self, status_code=200, text="", payload=None, url="https://x/"):
        self.status_code = status_code
        self.text = text
        self._payload = payload
        self.url = url

    def json(self):
        if self._payload is None:
            raise ValueError("no json")
        return self._payload


class FakeSession:
    """Records requests and replays scripted responses in order."""

    def __init__(self, responses):
        self.responses = list(responses)
        self.calls = []
        self.headers = {}
        self.cookies = None

    def get(self, url, params=None, **kwargs):
        self.calls.append((url, params))
        if not self.responses:
            raise AssertionError(f"unexpected request: {url}")
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def make_client(responses, *, key=KEY):
    tmp = tempfile.mkdtemp()
    c = client_mod.AnnasClient(key=key, state_dir=Path(tmp))
    c.session = FakeSession(responses)
    c._base = "https://annas-archive.gd"
    return c


class SearchFallbackTests(unittest.TestCase):
    def test_ddos_guard_403_falls_back_to_libgen(self):
        libgen_html = (FIXTURES / "libgen-search.html").read_text(encoding="utf-8")
        c = make_client(
            [
                FakeResponse(403, "<title>DDoS-Guard</title>"),
                FakeResponse(200, libgen_html),
            ]
        )
        books = c.search("interpretation of computer programs")
        self.assertEqual(len(books), 2)
        self.assertTrue(all(b.source == "libgen" for b in books))
        self.assertIn("annas-archive.gd/search", c.session.calls[0][0])
        self.assertIn("libgen", c.session.calls[1][0])

    def test_challenge_body_on_a_200_also_falls_back(self):
        libgen_html = (FIXTURES / "libgen-search.html").read_text(encoding="utf-8")
        c = make_client(
            [
                FakeResponse(200, "<html><title>DDoS-Guard</title></html>"),
                FakeResponse(200, libgen_html),
            ]
        )
        self.assertEqual(len(c.search("x")), 2)

    def test_annas_html_is_used_when_it_answers(self):
        aa_html = (FIXTURES / "annas-search.html").read_text(encoding="utf-8")
        c = make_client([FakeResponse(200, aa_html)])
        books = c.search("x")
        self.assertEqual(len(books), 2)
        self.assertTrue(all(b.source == "annas-archive" for b in books))

    def test_libgen_mirrors_are_tried_in_order(self):
        libgen_html = (FIXTURES / "libgen-search.html").read_text(encoding="utf-8")
        c = make_client(
            [
                FakeResponse(403, "DDoS-Guard"),
                FakeResponse(502, ""),
                FakeResponse(200, libgen_html),
            ]
        )
        self.assertEqual(len(c.search("x")), 2)
        self.assertIn(client_mod.LIBGEN_BASES[0], c.session.calls[1][0])
        self.assertIn(client_mod.LIBGEN_BASES[1], c.session.calls[2][0])


class FastDownloadTests(unittest.TestCase):
    MD5 = "2f8800a7b88c5c81eea1a04c6fa3e1bc"

    def test_key_travels_in_params_not_in_the_url(self):
        c = make_client([FakeResponse(200, payload={"download_url": "https://d/x.pdf"})])
        c.fast_download(self.MD5)
        url, params = c.session.calls[0]
        self.assertNotIn(KEY, url)
        self.assertEqual(params["key"], KEY)
        self.assertEqual(params["md5"], self.MD5)

    def test_bad_md5_is_reported_as_400(self):
        c = make_client([FakeResponse(400, "{}")])
        with self.assertRaises(client_mod.ClientError) as ctx:
            c.fast_download(self.MD5)
        self.assertIn("400", str(ctx.exception))

    def test_bad_key_is_reported_as_401_without_echoing_the_key(self):
        c = make_client([FakeResponse(401, "{}")])
        with self.assertRaises(client_mod.ClientError) as ctx:
            c.fast_download(self.MD5)
        self.assertIn("401", str(ctx.exception))
        self.assertNotIn(KEY, str(ctx.exception))

    def test_optional_indices_are_passed_through(self):
        c = make_client([FakeResponse(200, payload={"download_url": "u"})])
        c.fast_download(self.MD5, path_index=1, domain_index=2)
        _, params = c.session.calls[0]
        self.assertEqual(params["path_index"], 1)
        self.assertEqual(params["domain_index"], 2)

    def test_no_key_is_refused_before_any_request(self):
        c = make_client([], key=None)
        with self.assertRaises(client_mod.ClientError):
            c.fast_download(self.MD5)
        self.assertEqual(c.session.calls, [])


class FilenameTests(unittest.TestCase):
    MD5 = "2f8800a7b88c5c81eea1a04c6fa3e1bc"

    def test_name_from_url(self):
        name = client_mod._filename_for(
            "https://d.example/x/Some%20Book.pdf?token=1", self.MD5
        )
        self.assertEqual(name, "Some Book.pdf")

    def test_fallback_when_the_url_carries_no_name(self):
        self.assertEqual(
            client_mod._filename_for("https://d.example/download", self.MD5),
            f"{self.MD5}.bin",
        )


if __name__ == "__main__":
    unittest.main()
