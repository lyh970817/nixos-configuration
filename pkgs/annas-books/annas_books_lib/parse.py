"""md5 extraction and result parsing for Anna's Archive and LibGen pages.

An md5 is the only identifier the fast-download API takes, so getting one out of
whatever the user pasted -- a bare hash, an Anna's Archive URL, a LibGen mirror
link -- is the whole job of ``extract_md5``.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

_MD5_RE = re.compile(r"(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])")
_AA_MD5_HREF_RE = re.compile(r"/md5/([0-9a-fA-F]{32})")
_LIBGEN_MD5_HREF_RE = re.compile(r"md5=([0-9a-fA-F]{32})")


@dataclass
class Book:
    md5: str
    title: str = ""
    author: str = ""
    publisher: str = ""
    year: str = ""
    language: str = ""
    extension: str = ""
    size: str = ""
    source: str = ""

    def as_dict(self) -> dict:
        return dict(self.__dict__)


def extract_md5(value: str) -> str | None:
    """Pull a lowercase md5 out of a hash, an URL, or a pasted link."""
    if not value:
        return None
    m = _AA_MD5_HREF_RE.search(value) or _LIBGEN_MD5_HREF_RE.search(value)
    if m:
        return m.group(1).lower()
    m = _MD5_RE.search(value)
    return m.group(0).lower() if m else None


def _text(node) -> str:
    return " ".join(node.get_text(" ", strip=True).split()) if node else ""


def parse_annas_search(html: str, *, limit: int = 25) -> list[Book]:
    """Parse an Anna's Archive search page into books.

    Anna's Archive rewrites its markup often, so this leans on the one stable
    thing: every result links to ``/md5/<hash>``. Titles are taken from the
    link text when there is any.
    """
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "lxml")
    seen: dict[str, Book] = {}
    for anchor in soup.find_all("a", href=True):
        m = _AA_MD5_HREF_RE.search(anchor["href"])
        if not m:
            continue
        md5 = m.group(1).lower()
        if md5 in seen:
            continue
        text = _text(anchor)
        seen[md5] = Book(md5=md5, title=text, source="annas-archive")
        if len(seen) >= limit:
            break
    return list(seen.values())


def parse_libgen_search(html: str, *, limit: int = 25) -> list[Book]:
    """Parse a LibGen ``index.php`` result table into books.

    Anna's Archive indexes LibGen under the same md5, so an md5 found here is
    usable against the fast-download API. Column order in ``#tablelibgen`` is
    title, author, publisher, year, language, pages, size, extension, mirrors.
    """
    from bs4 import BeautifulSoup

    soup = BeautifulSoup(html, "lxml")
    table = soup.find("table", id="tablelibgen") or soup.find("table")
    if table is None:
        return []

    books: list[Book] = []
    seen: set[str] = set()
    for row in table.find_all("tr"):
        cells = row.find_all("td")
        if len(cells) < 9:
            continue
        md5 = None
        for anchor in cells[-1].find_all("a", href=True):
            md5 = extract_md5(anchor["href"])
            if md5:
                break
        if not md5 or md5 in seen:
            continue
        seen.add(md5)

        title_cell = cells[0]
        title_link = title_cell.find("a")
        books.append(
            Book(
                md5=md5,
                title=_text(title_link) or _text(title_cell),
                author=_text(cells[1]),
                publisher=_text(cells[2]),
                year=_text(cells[3]),
                language=_text(cells[4]),
                size=_text(cells[6]),
                extension=_text(cells[7]),
                source="libgen",
            )
        )
        if len(books) >= limit:
            break
    return books
