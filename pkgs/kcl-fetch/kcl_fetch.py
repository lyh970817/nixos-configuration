#!/usr/bin/env python3
"""kcl-fetch -- one paywalled article at a time, through KCL.

The last rung of the paper ladder. `scansci-oa` is free and unattributed and
should be tried first; this tool spends institutional credit and puts KCL's
name on every request, so it exists for the case `scansci-oa` cannot serve --
in practice anything paywalled and published after the shadow libraries froze
in 2021.

Subcommands are `get`, `login` and `status`. There is no batch mode, and its
absence is the feature: bulk retrieval is the abuse signature that gets an
institution's whole IP range blocked.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

from kcl_fetch_lib import config as config_mod
from kcl_fetch_lib import display as display_mod
from kcl_fetch_lib import driver as driver_mod
from kcl_fetch_lib import libkey, metadata, paths, remote, routing, urls
from kcl_fetch_lib.gate import (
    ArticleMeta,
    Gate,
    GateRefusal,
    PublisherBlocked,
)
from kcl_fetch_lib.limits import LimitsConfigError
from kcl_fetch_lib.pdfcheck import NotAPdf

#: Baked in by the Nix wrapper. Falling back to PATH keeps the module runnable
#: from a checkout without pretending it found a browser it did not.
CHROMIUM_ENV = "KCL_FETCH_CHROMIUM"


def _resolve_chromium(configured: str | None) -> str:
    for candidate in (configured, os.environ.get(CHROMIUM_ENV)):
        if candidate and Path(candidate).exists():
            return candidate
    found = shutil.which("chromium") or shutil.which("chromium-browser")
    if found:
        return found
    raise SystemExit(
        "kcl-fetch: no chromium binary. Playwright must never download its own "
        f"(the prebuilt binaries do not run on NixOS); set ${CHROMIUM_ENV}."
    )


def _display(args) -> display_mod.Display:
    """Resolve the display before anything is spent on the attempt.

    Called first in every subcommand that opens a window, so a session-less
    shell costs neither a gate slot nor a browser launch. `NoDisplay` is caught
    in `main` and printed as one line.
    """
    resolved = display_mod.resolve(args.ozone_platform)
    if getattr(args, "verbose", False):
        print(
            f"kcl-fetch: display -- {resolved.platform} via {resolved.detail}",
            file=sys.stderr,
        )
        for name, value in sorted(resolved.env.items()):
            print(f"kcl-fetch: display -- {name}={value}", file=sys.stderr)
    return resolved


def _doi_stem(doi: str) -> str:
    return doi.replace("/", "_").replace(":", "_")


def _open_gate(cfg: config_mod.Config) -> Gate:
    paths.ensure(paths.state_dir())
    return Gate(
        db_path=paths.ledger_path(),
        lock_path=paths.lock_path(),
        limits=cfg.limits,
    )


# ---------------------------------------------------------------------------
# get


def cmd_get(args, cfg: config_mod.Config) -> int:
    # Before LibKey, before Crossref, before the gate: a fetch that cannot open
    # a window should not consume a budget slot discovering that.
    screen = _display(args)

    doi = urls.normalise_doi(args.doi)
    if not urls.is_doi(doi):
        print(f"kcl-fetch: {args.doi!r} is not a DOI", file=sys.stderr)
        return 2

    # LibKey first: it is outside the gate because it never touches a publisher
    # or the institution's IP reputation, and answering "KCL does not hold this"
    # here saves a browser launch and a gated request.
    try:
        holding = libkey.precheck(doi)
    except PermissionError as exc:
        print(f"kcl-fetch: {exc}", file=sys.stderr)
        return 2
    if holding is not None and not holding.full_text:
        print(
            f"kcl-fetch: LibKey reports no KCL full text for {doi}. "
            "Try `scansci-oa` for a preprint, or request it via inter-library loan.",
            file=sys.stderr,
        )
        return 1
    if holding is not None and holding.retracted:
        print(f"kcl-fetch: warning -- LibKey flags {doi} as retracted", file=sys.stderr)

    # Crossref supplies both the enumeration metadata and the publisher's own
    # landing URL. The landing URL matters twice over: it is what the per-host
    # cooldown, the routing table and any 403 latch key on, and learning it
    # here means we never have to follow the DOI redirect -- which would be a
    # publisher request made before the gate could refuse it.
    record = metadata.lookup(doi)
    meta = record.meta
    if holding is not None and holding.meta.issue_key():
        meta = holding.meta

    target = record.landing_url or urls.doi_url(doi)
    host = urls.host_of(target) or "doi.org"
    table = routing.RoutingTable(paths.routes_path())
    gate = _open_gate(cfg)

    out_dir = Path(args.output).expanduser()
    chromium = _resolve_chromium(cfg.chromium)

    try:
        for template in table.order(host):
            access_url = urls.build(template, target)
            try:
                attempt = gate.acquire(host, doi, meta)
            except GateRefusal as refusal:
                print(f"kcl-fetch: refused -- {refusal.advice()}", file=sys.stderr)
                return 3

            with attempt:
                try:
                    with driver_mod.Browser(
                        profile_dir=paths.profile_dir(),
                        chromium=chromium,
                        downloads_dir=paths.ensure(paths.state_dir() / "downloads"),
                        extra_args=screen.ozone_args(),
                        env=screen.env,
                    ) as browser:
                        result = browser.fetch_pdf(
                            access_url,
                            doi=doi,
                            template=template,
                            out_dir=out_dir,
                            stem=_doi_stem(doi),
                            min_bytes=cfg.limits.min_pdf_bytes,
                        )
                except driver_mod.AccessForbidden as forbidden:
                    try:
                        attempt.blocked(forbidden.status, str(forbidden))
                    except PublisherBlocked as blocked:
                        print(f"kcl-fetch: {blocked.advice()}", file=sys.stderr)
                    return 4
                except driver_mod.LoginRequired as needed:
                    attempt.miss(str(needed))
                    print(f"kcl-fetch: {needed}", file=sys.stderr)
                    return 5
                except (driver_mod.NoFullText, NotAPdf) as miss:
                    attempt.miss(str(miss))
                    table.record(host, template, worked=False)
                    print(f"kcl-fetch: {template} route failed -- {miss}", file=sys.stderr)
                    continue

                attempt.ok(str(result.path))

            table.record(result.provenance["publisher_host"], template, worked=True)
            print(f"kcl-fetch: {result.path}")
            print(
                f"kcl-fetch: {result.facts.size} bytes, "
                f"{result.facts.pages or '?'} pages, via {template} "
                f"({result.provenance['publisher_host']})"
            )
            return 0

        print(
            f"kcl-fetch: no institutional route served {doi}. "
            "Fall back to `scansci-oa`, or ask the library for a scan.",
            file=sys.stderr,
        )
        return 1
    finally:
        gate.close()


# ---------------------------------------------------------------------------
# login


def cmd_login(args, cfg: config_mod.Config) -> int:
    """One manual sign-in, reused until the session expires.

    Ungated: this is an SSO round trip, not a publisher fetch, and it must
    stay reachable even when the fetch budget is spent -- otherwise a spent
    budget would also lock the user out of renewing the session.
    """
    if args.on is not None:
        return _login_elsewhere(args)

    # Before the display probe, so it is also said when there turns out to be
    # no session here at all -- that is the same mistake, one step earlier.
    note = remote.ssh_hint()
    if note:
        print(note, file=sys.stderr)

    screen = _display(args)
    chromium = _resolve_chromium(cfg.chromium)
    start = urls.openathens_url("https://my.openathens.net/")
    print(
        "kcl-fetch: a Chromium window is opening.\n"
        "  Sign in as k1234567@kcl.ac.uk, then approve the Microsoft "
        "Authenticator prompt.\n"
        "  MFA is enforced, so this step cannot be automated and is never "
        "attempted.\n"
        "  The window closes by itself once you are through.",
        file=sys.stderr,
    )
    with driver_mod.Browser(
        profile_dir=paths.profile_dir(),
        chromium=chromium,
        downloads_dir=paths.ensure(paths.state_dir() / "downloads"),
        extra_args=screen.ozone_args(),
        env=screen.env,
    ) as browser:
        if browser.interactive_login(start, wait_seconds=args.timeout):
            print("kcl-fetch: signed in; the session is stored in the profile.")
            return 0
    print("kcl-fetch: sign-in did not complete", file=sys.stderr)
    return 1


def _stdin_is_tty() -> bool:
    try:
        return sys.stdin is not None and sys.stdin.isatty()
    except (AttributeError, ValueError):
        return False


def _login_elsewhere(args) -> int:
    """`--on HOST`: the same sign-in, one SSH hop away, on that host's profile."""
    try:
        host = remote.resolve_host(args.on)
    except remote.RemoteError as exc:
        print(f"kcl-fetch: {exc}", file=sys.stderr)
        return 2
    print(
        f"kcl-fetch: running the sign-in on {host}; the window opens there.",
        file=sys.stderr,
    )
    try:
        status = remote.dispatch_login(
            host,
            timeout=args.timeout,
            ozone_platform=args.ozone_platform,
            verbose=args.verbose,
            # A tty lets an interrupt reach the far side, so aborting here also
            # closes the browser there.
            tty=_stdin_is_tty(),
        )
    except remote.RemoteError as exc:
        print(f"kcl-fetch: {exc}", file=sys.stderr)
        return 2
    if status == remote.SSH_FAILURE_STATUS:
        print(
            f"kcl-fetch: ssh never reached {host}; the sign-in did not start.",
            file=sys.stderr,
        )
    return status


# ---------------------------------------------------------------------------
# status


def cmd_status(args, cfg: config_mod.Config) -> int:
    gate = _open_gate(cfg)
    try:
        state = gate.budget_state()
        for label, (used, cap, window) in state.items():
            print(f"{label:>6} budget: {used}/{cap} in the last {window / 3600:g}h")
        blocks = gate.db.execute("SELECT * FROM blocks ORDER BY ts").fetchall()
        if blocks:
            print("\nlatched blocks (need the library, not a retry):")
            for row in blocks:
                print(f"  {row['host']}  status={row['status']}  doi={row['doi']}")
        else:
            print("\nno latched publisher blocks")
        recent = gate.recent(args.limit)
        if recent:
            print("\nrecent attempts:")
            for row in recent:
                print(f"  {row['outcome']:<20} {row['host']:<28} {row['doi']}")
        print(f"\nprofile: {paths.profile_dir()}")
        print(f"ledger:  {paths.ledger_path()}")
        return 0
    finally:
        gate.close()


# ---------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="kcl-fetch",
        description=(
            "Fetch one paywalled article through King's College London. "
            "Try scansci-oa first; there is deliberately no batch mode."
        ),
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # Shared by the two subcommands that open a window. `status` never does.
    browser_opts = argparse.ArgumentParser(add_help=False)
    browser_opts.add_argument(
        "--ozone-platform",
        metavar="PLATFORM",
        help=(
            "Chromium ozone platform (wayland, x11). Default: whichever of a "
            "Wayland socket in $XDG_RUNTIME_DIR or an X socket in "
            "/tmp/.X11-unix is actually there, Wayland first. An explicit "
            "value is used even if its socket was not found."
        ),
    )
    browser_opts.add_argument(
        "--verbose",
        action="store_true",
        help="report which display was chosen and why",
    )

    get = sub.add_parser(
        "get", parents=[browser_opts], help="fetch one article by DOI"
    )
    get.add_argument("doi")
    get.add_argument("-o", "--output", default=".", metavar="DIR")
    get.set_defaults(func=cmd_get)

    login = sub.add_parser(
        "login",
        parents=[browser_opts],
        help="one-time manual SSO in a visible window",
    )
    login.add_argument("--timeout", type=float, default=900.0, metavar="SECONDS")
    peer = remote.peer_host()
    login.add_argument(
        "--on",
        nargs="?",
        const=remote.PEER,
        metavar="HOST",
        help=(
            "run the sign-in on HOST over SSH, so the window opens on that "
            "machine's screen -- against its own profile, which is where its "
            "session belongs. With no value: "
            + (f"{peer}." if peer else f"${remote.PEER_HOST_ENV}, unset here.")
        ),
    )
    login.set_defaults(func=cmd_login)

    status = sub.add_parser("status", help="budget, blocks and recent attempts")
    status.add_argument("--limit", type=int, default=15)
    status.set_defaults(func=cmd_status)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        cfg = config_mod.load()
    except LimitsConfigError as exc:
        print(f"kcl-fetch: {exc}", file=sys.stderr)
        return 2
    try:
        return args.func(args, cfg)
    except (
        display_mod.NoDisplay,
        driver_mod.StaleProfileLock,
        remote.RemoteError,
    ) as exc:
        # All three are facts about the machine -- no session, a profile
        # already in use, no way to reach the host asked for -- not failures of
        # the tool. One line, no traceback, no Chromium flag dump.
        print(f"kcl-fetch: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
