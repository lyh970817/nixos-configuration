"""Institutional access URLs for King's College London.

KCL is Shibboleth/OpenAthens primary; EZproxy covers only about a fifth of the
subscribed resources, so it is the fallback rather than the route.

The two templates are not the same kind of thing, and treating them as
interchangeable proxies is the usual mistake:

* The OpenAthens redirector is a **WAYFless URL generator**. It answers 302 to
  the publisher's own SSO start endpoint with KCL's IdP entityID injected, and
  then it is out of the picture -- the browser talks to the publisher directly
  and the publisher sets its own SP session cookie.
* EZproxy is a real rewriting proxy: the session rides on
  `login.kcl.idm.oclc.org`, and abuse counts against the proxy's `UsageLimit`
  rather than against the publisher.

The legacy `libproxy.kcl.ac.uk` host is dead and is not offered.
"""

from __future__ import annotations

import urllib.parse

OPENATHENS_REDIRECTOR = "https://go.openathens.net/redirector/kcl.ac.uk"
EZPROXY_LOGIN = "https://login.kcl.idm.oclc.org/login"

#: KCL's Shibboleth IdP, as injected by the redirector. Recorded for provenance
#: and for recognising an IdP page during login-wall detection.
KCL_IDP_ENTITY_ID = "https://kclidp.kcl.ac.uk/idp/shibboleth"

#: Where `login` aims the redirector. Reaching *this* page is the proof the
#: whole OpenAthens hop ran: the redirector itself answers on a different host
#: and proves nothing.
OPENATHENS_PORTAL = "https://my.openathens.net/"

DOI_RESOLVER = "https://doi.org/"

OPENATHENS = "openathens"
EZPROXY = "ezproxy"
TEMPLATES = (OPENATHENS, EZPROXY)


def normalise_doi(doi: str) -> str:
    """Strip the usual decorations people paste around a DOI."""
    text = doi.strip()
    for prefix in (
        "https://doi.org/",
        "http://doi.org/",
        "https://dx.doi.org/",
        "http://dx.doi.org/",
        "doi:",
        "DOI:",
    ):
        if text.lower().startswith(prefix.lower()):
            text = text[len(prefix) :]
            break
    return text.strip()


def is_doi(text: str) -> bool:
    return normalise_doi(text).startswith("10.")


def doi_url(doi: str) -> str:
    """A resolver URL for a DOI, encoded so awkward suffixes survive.

    Real DOIs contain `<`, `>`, `;`, `(`, `)`, `#` and `?` -- the old Wiley
    SICI suffixes are the standing example. Everything except the structural
    `/` is percent-encoded; over-encoding a path segment is harmless, while
    leaving `#` or `?` raw truncates the DOI at the fragment or query.
    """
    return DOI_RESOLVER + urllib.parse.quote(normalise_doi(doi), safe="/")


def openathens_url(target: str) -> str:
    """Wrap a target URL in KCL's OpenAthens redirector."""
    return f"{OPENATHENS_REDIRECTOR}?url={urllib.parse.quote(target, safe='')}"


def ezproxy_url(target: str) -> str:
    """Wrap a target URL in KCL's EZproxy starting point."""
    return f"{EZPROXY_LOGIN}?url={urllib.parse.quote(target, safe='')}"


def build(template: str, target: str) -> str:
    if template == OPENATHENS:
        return openathens_url(target)
    if template == EZPROXY:
        return ezproxy_url(target)
    raise ValueError(f"unknown access template {template!r}")


def host_of(url: str) -> str:
    """The registrable-ish host of a URL, lowercased, `www.` dropped."""
    host = (urllib.parse.urlsplit(url).hostname or "").casefold()
    return host[4:] if host.startswith("www.") else host
