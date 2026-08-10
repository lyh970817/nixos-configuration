#!/usr/bin/env python3
"""Launch a fresh, resumed, or forked Codex session for a prepared handoff."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import subprocess
import sys
import tempfile
from typing import Any


PROFILE_ARGS = ["--profile", "orchestrator", "--dangerously-bypass-approvals-and-sandbox"]
PROMPT_TIMEOUT_MS = "120000"


class HandoffError(RuntimeError):
    """A handoff operation failed."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("fresh", "resume", "fork"), default="fresh")
    parser.add_argument("--session-id")
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--consume-briefing", action="store_true")
    parser.add_argument("--briefing-file", required=True)
    args = parser.parse_args()
    if args.mode in {"resume", "fork"} and not args.session_id:
        parser.error(f"--session-id is required for {args.mode}")
    if args.mode == "fresh" and args.session_id:
        parser.error("--session-id is not valid for fresh mode")
    return args


def run(command: list[str], *, display: str | None = None) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(command, text=True, capture_output=True, check=False)
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip() or "no error output"
        raise HandoffError(f"{display or shlex.join(command)} failed: {detail}")
    return completed


def run_json(command: list[str]) -> dict[str, Any]:
    completed = run(command)
    try:
        value = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise HandoffError(f"{shlex.join(command)} returned invalid JSON: {error}") from error
    if not isinstance(value, dict):
        raise HandoffError(f"{shlex.join(command)} returned a non-object JSON value")
    return value


def secure_briefing_copy(source: Path) -> Path:
    try:
        briefing = source.read_text(encoding="utf-8")
    except OSError as error:
        raise HandoffError(f"cannot read briefing {source}: {error}") from error
    if not briefing.strip():
        raise HandoffError("briefing is empty")
    fd, raw_path = tempfile.mkstemp(prefix="codex-handoff-", suffix=".md")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            fd = -1
            handle.write(briefing)
    except BaseException:
        if fd >= 0:
            os.close(fd)
        os.unlink(raw_path)
        raise
    return Path(raw_path)


def consume_briefing_source(source: Path, preserved_copy: Path) -> None:
    try:
        source.unlink()
    except OSError as error:
        raise HandoffError(
            f"cannot consume briefing {source}: {error}; "
            f"secure copy preserved at {preserved_copy}"
        ) from error


def codex_args(mode: str, cwd: Path, session_id: str | None) -> list[str]:
    args = [*PROFILE_ARGS, "--cd", str(cwd)]
    if mode != "fresh":
        assert session_id is not None
        args.extend((mode, session_id))
    return args


def manual_command(mode: str, cwd: Path, session_id: str | None, briefing: Path) -> str:
    prompt = f"Read the session handoff briefing at {briefing} and continue the work."
    return shlex.join(["codex", *codex_args(mode, cwd, session_id), "--", prompt])


def caller_rect(layout_result: dict[str, Any], caller_id: str) -> dict[str, int]:
    try:
        panes = layout_result["result"]["layout"]["panes"]
        pane = next(item for item in panes if item["pane_id"] == caller_id)
        rect = pane["rect"]
        return {"width": int(rect["width"]), "height": int(rect["height"])}
    except (KeyError, StopIteration, TypeError, ValueError) as error:
        raise HandoffError(f"caller pane {caller_id!r} is absent from Herdr layout") from error


def split_pane(caller_id: str, cwd: Path) -> str:
    layout = run_json(["herdr", "pane", "layout", "--pane", caller_id])
    rect = caller_rect(layout, caller_id)
    direction = "right" if rect["width"] >= 2 * rect["height"] else "down"
    result = run_json(
        [
            "herdr",
            "pane",
            "split",
            "--pane",
            caller_id,
            "--direction",
            direction,
            "--ratio",
            "0.5",
            "--cwd",
            str(cwd),
            "--no-focus",
        ]
    )
    try:
        pane_id = result["result"]["pane"]["pane_id"]
    except (KeyError, TypeError) as error:
        raise HandoffError("Herdr split response did not contain a pane ID") from error
    if not isinstance(pane_id, str) or not pane_id:
        raise HandoffError("Herdr split returned an invalid pane ID")
    return pane_id


def launch_in_herdr(
    mode: str,
    cwd: Path,
    session_id: str | None,
    briefing: str,
    briefing_path: Path,
) -> int:
    caller_id = os.environ.get("HERDR_PANE_ID")
    if not caller_id:
        raise HandoffError("HERDR_ENV=1 but HERDR_PANE_ID is missing")
    if not shutil.which("herdr"):
        raise HandoffError("HERDR_ENV=1 but the herdr executable is unavailable")

    pane_id: str | None = None
    agent_name: str | None = None
    try:
        pane_id = split_pane(caller_id, cwd)
        agent_name = f"handoff-{secrets.token_hex(6)}"
        run(
            [
                "herdr",
                "agent",
                "start",
                agent_name,
                "--kind",
                "codex",
                "--pane",
                pane_id,
                "--timeout",
                PROMPT_TIMEOUT_MS,
                "--",
                *codex_args(mode, cwd, session_id),
            ]
        )
        prompt_command = [
            "herdr",
            "agent",
            "prompt",
            agent_name,
            briefing,
            "--wait",
            "--until",
            "working",
            "--until",
            "blocked",
            "--until",
            "idle",
            "--until",
            "done",
            "--timeout",
            PROMPT_TIMEOUT_MS,
        ]
        run(
            prompt_command,
            display=f"herdr agent prompt {agent_name} <briefing> --wait",
        )
    except HandoffError as error:
        print(f"handoff failed: {error}", file=sys.stderr)
        if pane_id:
            print(f"preserved pane: {pane_id}", file=sys.stderr)
        if agent_name:
            print(f"agent name: {agent_name}", file=sys.stderr)
        print(f"briefing: {briefing_path}", file=sys.stderr)
        return 1

    try:
        run(["herdr", "agent", "focus", agent_name])
    except HandoffError as error:
        print(f"warning: prompt accepted, but focus failed: {error}", file=sys.stderr)

    briefing_path.unlink(missing_ok=True)
    print(f"handoff accepted: mode={mode} pane={pane_id} agent={agent_name}")
    return 0


def main() -> int:
    args = parse_args()
    cwd = Path(args.cwd).expanduser().resolve()
    if not cwd.is_dir():
        raise HandoffError(f"cwd is not a directory: {cwd}")
    briefing_source = Path(args.briefing_file).expanduser()
    briefing_path = secure_briefing_copy(briefing_source)
    if args.consume_briefing:
        consume_briefing_source(briefing_source, briefing_path)
    briefing = briefing_path.read_text(encoding="utf-8")

    if os.environ.get("HERDR_ENV") == "1":
        return launch_in_herdr(args.mode, cwd, args.session_id, briefing, briefing_path)

    print(f"briefing saved: {briefing_path}")
    print("manual command:")
    print(manual_command(args.mode, cwd, args.session_id, briefing_path))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except HandoffError as error:
        print(f"handoff failed: {error}", file=sys.stderr)
        raise SystemExit(1)
