#!/usr/bin/env python3
"""annas-books -- Anna's Archive membership client, books only.

Papers are out of scope on purpose: Anna's Archive serves the same Sci-Hub
corpus scansci-oa already reaches for free, and every download here spends one
unit of a per-day membership quota. There is no batch command for the same
reason.

The membership key comes from $ANNAS_SECRET_KEY or a 0600 file (default
$XDG_CONFIG_HOME/annas-books/secret-key). It is never passed on the command
line -- it travels in a query string, so argv would leak it to `ps`, to shell
history, and to logs.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from annas_books_lib import parse  # noqa: E402
from annas_books_lib.client import AnnasClient, ClientError  # noqa: E402
from annas_books_lib.mirrors import NoMirrorError  # noqa: E402
from annas_books_lib.secrets import ENV_VAR, MissingKeyError, load_key, redact  # noqa: E402


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "state"
    )
    return Path(base) / "annas-books"


def _client(*, need_key: bool) -> AnnasClient:
    key = None
    if need_key:
        key = load_key()
    else:
        try:
            key = load_key()
        except MissingKeyError:
            key = None
    return AnnasClient(key=key, state_dir=state_dir())


def _print_books(books: list[parse.Book], as_json: bool) -> None:
    if as_json:
        print(json.dumps([b.as_dict() for b in books], indent=2, ensure_ascii=False))
        return
    if not books:
        print("no results")
        return
    for book in books:
        bits = [b for b in (book.author, book.year, book.publisher) if b]
        meta = " | ".join(bits)
        fmt = " ".join(b for b in (book.extension, book.size) if b)
        print(f"{book.md5}  {book.title}")
        if meta:
            print(f"{'':34}{meta}")
        if fmt:
            print(f"{'':34}{fmt}  [{book.source}]")
    print(f"\n{len(books)} result(s). Download with: annas-books get <md5>")


def _report_quota(info: dict) -> None:
    """Surface what is left of the daily fast-download allowance."""
    if not info:
        print("quota: not reported by the server", file=sys.stderr)
        return
    left = info.get("downloads_left")
    total = info.get("downloads_per_day")
    if left is not None:
        suffix = f" of {total}" if total is not None else ""
        print(f"\n*** fast downloads left today: {left}{suffix} ***", file=sys.stderr)
    else:
        print(f"quota info: {json.dumps(info, ensure_ascii=False)}", file=sys.stderr)


def cmd_login(args) -> int:
    client = _client(need_key=True)
    print(client.login())
    print(f"cookie jar: {client.cookie_path} (0600)")
    return 0


def cmd_search(args) -> int:
    query = args.query
    if args.author:
        query = f"{query} {args.author}"
    client = _client(need_key=False)
    _print_books(client.search(query, limit=args.limit), args.json)
    return 0


def cmd_isbn(args) -> int:
    isbn = "".join(ch for ch in args.isbn if ch.isalnum())
    client = _client(need_key=False)
    _print_books(client.search(isbn, limit=args.limit), args.json)
    return 0


def cmd_get(args) -> int:
    md5 = parse.extract_md5(args.md5)
    if not md5:
        print(f"annas-books: not an md5: {args.md5}", file=sys.stderr)
        return 2
    client = _client(need_key=True)
    target = client.download(md5, Path(args.output), on_quota=_report_quota)
    size = target.stat().st_size
    print(f"{target} ({size} bytes)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="annas-books",
        description="Anna's Archive membership client for books.",
        epilog=f"Key: ${ENV_VAR} or a 0600 file; never passed as an argument.",
    )
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("login", help="exchange the key for a session cookie")
    p.set_defaults(func=cmd_login)

    p = sub.add_parser("search", help="search books by title")
    p.add_argument("query")
    p.add_argument("--author", default="", help="narrow the search by author")
    p.add_argument("--limit", type=int, default=25)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("isbn", help="search books by ISBN")
    p.add_argument("isbn")
    p.add_argument("--limit", type=int, default=25)
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_isbn)

    p = sub.add_parser("get", help="download one book by md5 (spends quota)")
    p.add_argument("md5", help="md5 hash, or a URL containing one")
    p.add_argument("-o", "--output", default=".", help="output directory")
    p.set_defaults(func=cmd_get)

    return ap


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except MissingKeyError as exc:
        print(f"annas-books: {exc}", file=sys.stderr)
        return 3
    except NoMirrorError as exc:
        print(f"annas-books: {exc}", file=sys.stderr)
        return 4
    except ClientError as exc:
        # Belt and braces: ClientError messages are already scrubbed.
        print(f"annas-books: {redact(str(exc))}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
