"""md5 extraction and search-result parsing."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from annas_books_lib import parse  # noqa: E402

FIXTURES = Path(__file__).resolve().parent / "fixtures"


class ExtractMd5Tests(unittest.TestCase):
    MD5 = "2f8800a7b88c5c81eea1a04c6fa3e1bc"

    def test_bare_hash(self):
        self.assertEqual(parse.extract_md5(self.MD5), self.MD5)

    def test_uppercase_is_normalised(self):
        self.assertEqual(parse.extract_md5(self.MD5.upper()), self.MD5)

    def test_annas_url(self):
        url = f"https://annas-archive.gd/md5/{self.MD5}?r=Ax2w6jC"
        self.assertEqual(parse.extract_md5(url), self.MD5)

    def test_libgen_ads_url(self):
        url = f"https://libgen.la/ads.php?md5={self.MD5}"
        self.assertEqual(parse.extract_md5(url), self.MD5)

    def test_url_md5_wins_over_other_hex_in_the_string(self):
        other = "0" * 32
        url = f"https://x/{other}/md5/{self.MD5}"
        self.assertEqual(parse.extract_md5(url), self.MD5)

    def test_rejects_short_and_long_hex(self):
        self.assertIsNone(parse.extract_md5("abc123"))
        self.assertIsNone(parse.extract_md5("a" * 31))
        self.assertIsNone(parse.extract_md5("a" * 33))

    def test_rejects_non_hex(self):
        self.assertIsNone(parse.extract_md5("z" * 32))

    def test_empty(self):
        self.assertIsNone(parse.extract_md5(""))
        self.assertIsNone(parse.extract_md5(None))


class LibgenParseTests(unittest.TestCase):
    def setUp(self):
        self.html = (FIXTURES / "libgen-search.html").read_text(encoding="utf-8")
        self.books = parse.parse_libgen_search(self.html)

    def test_finds_every_row_once(self):
        self.assertEqual(len(self.books), 2)
        self.assertEqual(len({b.md5 for b in self.books}), 2)

    def test_extracts_metadata(self):
        book = self.books[0]
        self.assertEqual(book.md5, "2f8800a7b88c5c81eea1a04c6fa3e1bc")
        self.assertIn("Structure and Interpretation", book.title)
        self.assertIn("Abelson", book.author)
        self.assertEqual(book.publisher, "The MIT Press")
        self.assertEqual(book.year, "1996")
        self.assertEqual(book.language, "English")
        self.assertEqual(book.extension, "pdf")
        self.assertEqual(book.size, "4 MB")
        self.assertEqual(book.source, "libgen")

    def test_limit_is_honoured(self):
        self.assertEqual(len(parse.parse_libgen_search(self.html, limit=1)), 1)

    def test_empty_page(self):
        self.assertEqual(parse.parse_libgen_search("<html></html>"), [])


class AnnasParseTests(unittest.TestCase):
    def setUp(self):
        self.html = (FIXTURES / "annas-search.html").read_text(encoding="utf-8")

    def test_dedupes_and_ignores_non_record_links(self):
        books = parse.parse_annas_search(self.html)
        self.assertEqual(
            [b.md5 for b in books],
            [
                "2f8800a7b88c5c81eea1a04c6fa3e1bc",
                "480fe74fe104d87fc504da0ef24d85af",
            ],
        )
        self.assertTrue(all(b.source == "annas-archive" for b in books))

    def test_titles_come_from_link_text(self):
        books = parse.parse_annas_search(self.html)
        self.assertIn("Structure and Interpretation", books[0].title)


if __name__ == "__main__":
    unittest.main()
