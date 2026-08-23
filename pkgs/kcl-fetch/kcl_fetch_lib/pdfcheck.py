"""Is this actually the article, or a cover page pretending to be one?

Publishers serve a great many things with `Content-Type: application/pdf` that
are not the paper: a one-page "you do not have access" notice, a first-page
preview, a licence cover sheet. They are indistinguishable from the article by
status code and content type, so the check is on the bytes.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

_MAGIC = b"%PDF-"

#: `/Count N` on the page-tree root. Robust for linearised publisher PDFs;
#: absent when the page tree lives in a compressed object stream, in which case
#: we decline to guess rather than reject a real article.
_COUNT_RE = re.compile(rb"/Type\s*/Pages\b[^>]{0,400}?/Count\s+(\d+)", re.S)
_COUNT_FALLBACK_RE = re.compile(rb"/Count\s+(\d+)")
_PAGE_OBJ_RE = re.compile(rb"/Type\s*/Page[^s]")


class NotAPdf(ValueError):
    """The bytes are not a PDF, or not a plausible article PDF."""


@dataclass(frozen=True)
class PdfFacts:
    size: int
    pages: int | None


def page_count(data: bytes) -> int | None:
    for pattern in (_COUNT_RE, _COUNT_FALLBACK_RE):
        counts = [int(m.group(1)) for m in pattern.finditer(data)]
        if counts:
            return max(counts)
    found = len(_PAGE_OBJ_RE.findall(data))
    return found or None


def validate(path: Path, *, min_bytes: int, allow_single_page: bool = False) -> PdfFacts:
    path = Path(path)
    data = path.read_bytes()
    if not data.startswith(_MAGIC):
        raise NotAPdf(f"{path.name}: not a PDF (first bytes {data[:8]!r})")
    size = len(data)
    if size < min_bytes:
        raise NotAPdf(
            f"{path.name}: {size} bytes is below the {min_bytes}-byte floor -- "
            "almost certainly an access notice rather than the article"
        )
    pages = page_count(data)
    if pages == 1 and not allow_single_page:
        raise NotAPdf(
            f"{path.name}: single page -- this is a preview stub or a cover "
            "sheet, not the full text"
        )
    return PdfFacts(size=size, pages=pages)
