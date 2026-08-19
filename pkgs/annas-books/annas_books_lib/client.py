"""HTTP client for Anna's Archive (books) with a LibGen search fallback."""

from __future__ import annotations

import fcntl
import http.cookiejar
import os
import urllib.parse
from contextlib import contextmanager
from pathlib import Path

from . import mirrors, parse
from .secrets import redact

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/128.0 Safari/537.36"
)

CONNECT_TIMEOUT = 10
READ_TIMEOUT = 60

FAST_DOWNLOAD_PATH = "/dyn/api/fast_download.json"
ACCOUNT_PATH = "/account/"

#: LibGen mirrors that answer ``/index.php?req=`` for non-browsers. Used only
#: when Anna's Archive HTML is behind its DDoS-Guard JS challenge; the md5s are
#: the same ones Anna's Archive indexes.
LIBGEN_BASES = (
    "https://libgen.la",
    "https://libgen.vg",
    "https://libgen.bz",
    "https://libgen.li",
)


class ClientError(RuntimeError):
    """A request failed in a way the user needs to see."""


class ChallengeError(ClientError):
    """The page is behind the DDoS-Guard JS challenge."""


@contextmanager
def _quota_lock(path: Path):
    """Serialize quota-spending requests across concurrent invocations."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)


class AnnasClient:
    def __init__(self, *, key: str | None, state_dir: Path, bases=mirrors.DEFAULT_BASES):
        import requests

        self._key = key
        self.state_dir = state_dir
        self.bases = tuple(bases)
        self.session = requests.Session()
        self.session.headers["User-Agent"] = USER_AGENT
        self._base: str | None = None

        self.cookie_path = state_dir / "cookies.txt"
        self.session.cookies = http.cookiejar.MozillaCookieJar(str(self.cookie_path))
        if self.cookie_path.exists():
            try:
                self.session.cookies.load(ignore_discard=True, ignore_expires=True)
            except (OSError, http.cookiejar.LoadError):
                pass

    # -- plumbing ---------------------------------------------------------

    def scrub(self, text) -> str:
        return redact(text, self._key)

    def _probe(self, base: str) -> bool:
        import requests

        try:
            self.session.get(
                base + mirrors.PROBE_PATH,
                timeout=(CONNECT_TIMEOUT, 15),
                allow_redirects=False,
            )
        except requests.RequestException:
            return False
        return True

    @property
    def base(self) -> str:
        if self._base is None:
            self._base = mirrors.resolve_base(
                self._probe,
                bases=self.bases,
                cache_path=self.state_dir / "mirror.json",
            )
        return self._base

    # -- membership -------------------------------------------------------

    def login(self) -> str:
        """Exchange the key for a session cookie.

        Higher membership tiers advertise "no browser checks", so a logged-in
        cookie jar is what makes the HTML pages reachable at all. The key goes
        in the POST body, never the URL.
        """
        if not self._key:
            raise ClientError("no membership key loaded")
        resp = self.session.post(
            self.base + ACCOUNT_PATH,
            data={"key": self._key},
            timeout=(CONNECT_TIMEOUT, READ_TIMEOUT),
            allow_redirects=True,
        )
        if resp.status_code >= 400:
            raise ClientError(
                self.scrub(f"login failed: HTTP {resp.status_code} at {resp.url}")
            )
        self._save_cookies()
        names = sorted(c.name for c in self.session.cookies)
        if not names:
            raise ClientError(
                "login returned no cookies; the key may be wrong or the mirror "
                "may be serving a browser challenge"
            )
        return f"logged in to {self.base}; cookies: {', '.join(names)}"

    def _save_cookies(self) -> None:
        self.cookie_path.parent.mkdir(parents=True, exist_ok=True)
        # Create with 0600 before anything is written into it.
        fd = os.open(self.cookie_path, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
        os.close(fd)
        self.session.cookies.save(ignore_discard=True, ignore_expires=True)
        os.chmod(self.cookie_path, 0o600)

    # -- search -----------------------------------------------------------

    def search(self, query: str, *, limit: int = 25) -> list[parse.Book]:
        """Search books, falling back to LibGen when the HTML is challenged."""
        try:
            return self._search_annas(query, limit=limit)
        except ChallengeError:
            return self._search_libgen(query, limit=limit)

    def _search_annas(self, query: str, *, limit: int) -> list[parse.Book]:
        import requests

        url = self.base + "/search?" + urllib.parse.urlencode(
            {"q": query, "content": "book_any"}
        )
        try:
            resp = self.session.get(
                url, timeout=(CONNECT_TIMEOUT, READ_TIMEOUT), allow_redirects=True
            )
        except requests.RequestException as exc:
            raise ChallengeError(self.scrub(f"search request failed: {exc}")) from exc
        if resp.status_code == 403 or "DDoS-Guard" in resp.text[:2000]:
            raise ChallengeError("Anna's Archive served a browser challenge")
        if resp.status_code >= 400:
            raise ClientError(self.scrub(f"search failed: HTTP {resp.status_code}"))
        return parse.parse_annas_search(resp.text, limit=limit)

    def _search_libgen(self, query: str, *, limit: int) -> list[parse.Book]:
        import requests

        last = None
        for base in LIBGEN_BASES:
            url = base + "/index.php?" + urllib.parse.urlencode(
                {"req": query, "res": max(limit, 25)}
            )
            try:
                resp = self.session.get(url, timeout=(CONNECT_TIMEOUT, READ_TIMEOUT))
            except requests.RequestException as exc:
                last = exc
                continue
            if resp.status_code >= 400:
                last = ClientError(f"{base}: HTTP {resp.status_code}")
                continue
            books = parse.parse_libgen_search(resp.text, limit=limit)
            if books:
                return books
            return []
        raise ClientError(f"no LibGen mirror answered (last error: {last})")

    # -- download ---------------------------------------------------------

    def fast_download(self, md5: str, *, path_index=None, domain_index=None) -> dict:
        """Ask for a fast-download URL. Spends one unit of the daily quota."""
        import requests

        if not self._key:
            raise ClientError("no membership key loaded")
        params = {"md5": md5, "key": self._key}
        if path_index is not None:
            params["path_index"] = int(path_index)
        if domain_index is not None:
            params["domain_index"] = int(domain_index)

        url = self.base + FAST_DOWNLOAD_PATH
        try:
            resp = self.session.get(
                url, params=params, timeout=(CONNECT_TIMEOUT, READ_TIMEOUT)
            )
        except requests.RequestException as exc:
            raise ClientError(self.scrub(f"fast_download request failed: {exc}")) from exc

        if resp.status_code == 400:
            raise ClientError(f"Anna's Archive rejected the md5 {md5} (HTTP 400)")
        if resp.status_code == 401:
            raise ClientError(
                "Anna's Archive rejected the membership key (HTTP 401); check "
                "$ANNAS_SECRET_KEY or the key file"
            )
        if resp.status_code >= 400:
            raise ClientError(self.scrub(f"fast_download failed: HTTP {resp.status_code}"))
        try:
            return resp.json()
        except ValueError as exc:
            raise ClientError(self.scrub(f"fast_download returned non-JSON: {exc}")) from exc

    def download(self, md5: str, out_dir: Path, *, on_quota=None) -> Path:
        """Fetch one book. The download URL is temporary and single-use."""
        import requests

        with _quota_lock(self.state_dir / "quota.lock"):
            payload = self.fast_download(md5)
            url = payload.get("download_url")
            if not url:
                raise ClientError(
                    self.scrub(f"no download_url in response: {payload}")
                )
            if on_quota:
                on_quota(payload.get("account_fast_download_info") or {})

            out_dir.mkdir(parents=True, exist_ok=True)
            target = out_dir / _filename_for(url, md5)
            tmp = target.with_suffix(target.suffix + ".part")
            try:
                with self.session.get(
                    url, stream=True, timeout=(CONNECT_TIMEOUT, READ_TIMEOUT)
                ) as resp:
                    if resp.status_code >= 400:
                        raise ClientError(
                            self.scrub(f"download failed: HTTP {resp.status_code}")
                        )
                    with tmp.open("wb") as fh:
                        for chunk in resp.iter_content(chunk_size=1 << 16):
                            if chunk:
                                fh.write(chunk)
            except requests.RequestException as exc:
                tmp.unlink(missing_ok=True)
                raise ClientError(self.scrub(f"download failed: {exc}")) from exc
            tmp.replace(target)
            return target


def _filename_for(url: str, md5: str) -> str:
    name = os.path.basename(urllib.parse.urlparse(url).path)
    name = urllib.parse.unquote(name).strip()
    if name and "." in name and len(name) < 200:
        return name
    return f"{md5}.bin"
