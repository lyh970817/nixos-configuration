"""Publishers serve access notices with `Content-Type: application/pdf`."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from kcl_fetch_lib.pdfcheck import NotAPdf, page_count, validate

MIN = 1024


def pdf(pages: int | None, padding: int = 4096) -> bytes:
    body = b"%PDF-1.7\n"
    if pages is not None:
        body += b"1 0 obj\n<< /Type /Pages /Kids [] /Count %d >>\nendobj\n" % pages
    return body + b"%" + b"x" * padding + b"\n%%EOF\n"


class TestValidate(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def write(self, data: bytes) -> Path:
        path = self.root / "paper.pdf"
        path.write_bytes(data)
        return path

    def test_a_plausible_article_passes(self):
        facts = validate(self.write(pdf(14)), min_bytes=MIN)
        self.assertEqual(facts.pages, 14)

    def test_an_html_error_page_is_rejected(self):
        with self.assertRaises(NotAPdf):
            validate(self.write(b"<html>Access Denied</html>" + b" " * 8192), min_bytes=MIN)

    def test_a_tiny_file_is_rejected_even_with_the_right_magic(self):
        with self.assertRaises(NotAPdf) as caught:
            validate(self.write(pdf(9, padding=10)), min_bytes=MIN)
        self.assertIn("floor", str(caught.exception))

    def test_a_one_page_preview_stub_is_rejected(self):
        with self.assertRaises(NotAPdf) as caught:
            validate(self.write(pdf(1)), min_bytes=MIN)
        self.assertIn("single page", str(caught.exception))

    def test_a_genuinely_one_page_item_can_be_allowed_explicitly(self):
        facts = validate(self.write(pdf(1)), min_bytes=MIN, allow_single_page=True)
        self.assertEqual(facts.pages, 1)

    def test_an_undeterminable_page_count_is_not_a_rejection(self):
        # Compressed object streams hide the page tree. Refusing here would
        # throw away real articles to catch a stub we cannot see.
        facts = validate(self.write(pdf(None)), min_bytes=MIN)
        self.assertIsNone(facts.pages)


class TestPageCount(unittest.TestCase):
    def test_the_page_tree_count_is_preferred(self):
        self.assertEqual(page_count(pdf(23)), 23)

    def test_bare_page_objects_are_counted_when_no_tree_is_present(self):
        data = b"%PDF-1.4\n" + b"<< /Type /Page >>\n" * 7
        self.assertEqual(page_count(data), 7)


if __name__ == "__main__":
    unittest.main()
