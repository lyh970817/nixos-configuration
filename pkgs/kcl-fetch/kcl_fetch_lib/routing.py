"""Which access template works for which publisher, learned as we go.

The seed is a prior, not a fact: KCL is OpenAthens-primary, so every host
starts there and only moves to EZproxy if OpenAthens is observed to fail for
it. Nothing here is authoritative enough to hard-code, and a publisher can
change its SP configuration without telling anybody, so the table self-corrects
and is cached to disk rather than shipped in the Nix store.
"""

from __future__ import annotations

import json
from pathlib import Path

from .urls import EZPROXY, OPENATHENS, TEMPLATES

#: Publishers KCL subscribes to whose SP is known to speak Shibboleth. Listing
#: them changes nothing about the default -- it documents the prior and keeps
#: the file readable when a host does get flipped.
SEED: dict[str, str] = {
    host: OPENATHENS
    for host in (
        "sciencedirect.com",
        "onlinelibrary.wiley.com",
        "link.springer.com",
        "nature.com",
        "tandfonline.com",
        "journals.sagepub.com",
        "academic.oup.com",
        "cambridge.org",
        "ieeexplore.ieee.org",
        "dl.acm.org",
        "pubs.acs.org",
        "science.org",
        "jamanetwork.com",
        "thelancet.com",
        "bmj.com",
        "psycnet.apa.org",
        "karger.com",
        "degruyterbrill.com",
        "journals.lww.com",
        "pubs.rsc.org",
    )
}

DEFAULT_TEMPLATE = OPENATHENS


class RoutingTable:
    def __init__(self, path: Path):
        self.path = Path(path)
        self._learned: dict[str, str] = {}
        self._load()

    def _load(self) -> None:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return
        if isinstance(raw, dict):
            self._learned = {
                str(k).casefold(): str(v)
                for k, v in raw.get("hosts", {}).items()
                if v in TEMPLATES
            }

    def _save(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps({"hosts": self._learned}, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        tmp.replace(self.path)

    def _match(self, host: str) -> str | None:
        """Exact host, then parent domains, so `www.x.com` inherits from `x.com`."""
        host = host.casefold()
        labels = host.split(".")
        for start in range(len(labels) - 1):
            candidate = ".".join(labels[start:])
            for table in (self._learned, SEED):
                if candidate in table:
                    return table[candidate]
        return None

    def preferred(self, host: str) -> str:
        return self._match(host) or DEFAULT_TEMPLATE

    def order(self, host: str) -> list[str]:
        """Templates to try, best first. Both, always -- never more than two."""
        first = self.preferred(host)
        return [first] + [t for t in TEMPLATES if t != first]

    def record(self, host: str, template: str, *, worked: bool) -> None:
        host = host.casefold()
        if template not in TEMPLATES:
            return
        if worked:
            if self._learned.get(host) != template:
                self._learned[host] = template
                self._save()
            return
        # A failure only moves the host if the *other* template is left to try;
        # with two templates that means flipping to the other one.
        other = EZPROXY if template == OPENATHENS else OPENATHENS
        if self._learned.get(host) != other:
            self._learned[host] = other
            self._save()

    def as_dict(self) -> dict[str, str]:
        return {**SEED, **self._learned}
