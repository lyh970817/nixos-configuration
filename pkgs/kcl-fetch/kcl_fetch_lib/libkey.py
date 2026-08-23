"""LibKey pre-check: does KCL actually hold full text for this DOI?

One cheap API call answers that before a headed browser exists, which is the
difference between "KCL doesn't subscribe" costing nothing and costing a window
on screen plus a gated request against the budget.

The user has no LibKey key yet, so **unconfigured is a supported state**, not an
error: `precheck()` returns `None` and the caller proceeds to fetch. Getting a
key later only makes the tool cheaper, never differently correct.

Credentials follow the `annas-books` pattern -- environment first, otherwise a
0600 file outside the repository, never argv.
"""

from __future__ import annotations

import json
import os
import re
import stat
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from . import paths
from .gate import ArticleMeta

ENV_TOKEN = "KCL_LIBKEY_TOKEN"
ENV_LIBRARY = "KCL_LIBKEY_LIBRARY_ID"

API = "https://public-api.thirdiron.com/public/v1/libraries/{library}/articles/doi/{doi}"

USER_AGENT = "kcl-fetch/0.1 (personal single-article retrieval)"

#: The token travels in a query string, so it must never survive into a log
#: line, a provenance sidecar, or an error message.
_TOKEN_PARAM_RE = re.compile(r"(?i)\b(access_token=)[^&\s\"'<>]+")


def redact(text: str) -> str:
    return _TOKEN_PARAM_RE.sub(r"\1[REDACTED]", str(text))


@dataclass(frozen=True)
class LibKeyCredentials:
    library_id: str
    token: str


@dataclass(frozen=True)
class LibKeyResult:
    full_text: bool
    pdf_url: str | None
    content_location: str | None
    retracted: bool
    meta: ArticleMeta


def load_credentials(
    *, env: dict | None = None, key_file: Path | None = None
) -> LibKeyCredentials | None:
    """Credentials, or `None` when LibKey is simply not set up."""
    env = os.environ if env is None else env
    token = (env.get(ENV_TOKEN) or "").strip()
    library = (env.get(ENV_LIBRARY) or "").strip()
    if token and library:
        return LibKeyCredentials(library, token)

    path = paths.libkey_path() if key_file is None else Path(key_file)
    if not path.exists():
        return None
    mode = path.stat().st_mode
    if mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise PermissionError(
            f"{path} is group/world accessible; run: chmod 600 {path}"
        )
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return None
    token = str(raw.get("token", "")).strip()
    library = str(raw.get("library_id", "")).strip()
    if not (token and library):
        return None
    return LibKeyCredentials(library, token)


def _parse(payload: dict) -> LibKeyResult:
    data = payload.get("data") or {}
    included = payload.get("included") or []
    journal = None
    for item in included:
        if item.get("type") == "journals":
            journal = (item.get("attributes") or item).get("title") or item.get("title")
            break
    pdf = data.get("fullTextFile")
    return LibKeyResult(
        full_text=bool(pdf or data.get("contentLocation")),
        pdf_url=pdf,
        content_location=data.get("contentLocation"),
        retracted=bool(data.get("retractionNoticeUrl")),
        meta=ArticleMeta(
            journal=journal,
            volume=_str_or_none(data.get("volume")),
            issue=_str_or_none(data.get("issue")),
        ),
    )


def _str_or_none(value) -> str | None:
    if value is None or value == "":
        return None
    return str(value)


def precheck(
    doi: str,
    *,
    credentials: LibKeyCredentials | None = None,
    opener=None,
    timeout: float = 10.0,
) -> LibKeyResult | None:
    """Ask LibKey about `doi`, or return `None` if we can't or shouldn't.

    Every failure -- unconfigured, network, HTTP error, unparseable body -- is
    `None`. A pre-check that cannot answer must not be able to block a fetch;
    it is an optimisation, and an optimisation that fails closed would be worse
    than not having it.
    """
    credentials = credentials or load_credentials()
    if credentials is None:
        return None

    url = API.format(
        library=urllib.parse.quote(credentials.library_id, safe=""),
        doi=urllib.parse.quote(doi, safe="/"),
    ) + "?" + urllib.parse.urlencode({"access_token": credentials.token})
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        opener = opener or urllib.request.urlopen
        with opener(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        return None
    if not isinstance(payload, dict):
        return None
    return _parse(payload)
