"""What Crossref knows about a DOI, before anything institutional happens.

Two things are needed up front and neither is in the DOI string:

* **Journal, volume, issue** -- the gate's strongest rule (three DOIs from one
  issue is enumeration) is dead code without them.
* **The publisher's landing URL** -- so the per-host cooldown, the routing
  table and a 403 latch all key on the publisher rather than on `doi.org`.
  Following the DOI redirect to find that out would itself be a publisher
  request, made *before* the gate had a chance to refuse it.

Crossref is the right place to ask: free, unauthenticated, not a publisher, not
behind the institution, so the lookup neither spends the budget nor shows up in
anyone's abuse log.

Best-effort by construction. If Crossref is unreachable the issue rule goes
quiet for that DOI and the sequential-suffix rule, which needs nothing but the
string, still applies.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

from .gate import ArticleMeta

API = "https://api.crossref.org/works/"

#: Crossref asks for a contact address in the User-Agent for the polite pool.
USER_AGENT = "kcl-fetch/0.1 (mailto:lyh970817@yandex.com)"


@dataclass(frozen=True)
class Record:
    meta: ArticleMeta = ArticleMeta()
    landing_url: str | None = None


def lookup(doi: str, *, opener=None, timeout: float = 8.0) -> Record:
    url = API + urllib.parse.quote(doi, safe="/")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        opener = opener or urllib.request.urlopen
        with opener(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, OSError, ValueError, TimeoutError):
        return Record()
    message = (payload or {}).get("message") or {}
    titles = message.get("container-title") or []
    primary = ((message.get("resource") or {}).get("primary") or {}).get("URL")
    return Record(
        meta=ArticleMeta(
            journal=(titles[0] if titles else None) or None,
            volume=_text(message.get("volume")),
            issue=_text(message.get("issue")),
        ),
        landing_url=_text(primary),
    )


def _text(value) -> str | None:
    if value is None or value == "":
        return None
    return str(value)
