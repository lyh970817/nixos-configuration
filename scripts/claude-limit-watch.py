#!/usr/bin/env python3
"""Notify when Claude's five-hour limit is exhausted and resets."""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
from typing import Any, Iterator


FRESH_FOR = dt.timedelta(minutes=15)


def parse_time(value: Any) -> dt.datetime | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(dt.timezone.utc)


def format_time(value: dt.datetime) -> str:
    return value.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def numeric(value: Any) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
    )


def walk_windows(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        if value.get("windowMinutes") == 300 and numeric(value.get("usedPercent")):
            yield value
        for child in value.values():
            yield from walk_windows(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_windows(child)


def fresh_claude_windows(
    usage_file: Path, now: dt.datetime
) -> list[tuple[float, dt.datetime | None]] | None:
    try:
        document = json.loads(usage_file.read_text())
    except (OSError, json.JSONDecodeError):
        return None

    entries = document if isinstance(document, list) else [document]
    observations: list[tuple[float, dt.datetime | None]] = []
    found_fresh_provider = False
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("provider") != "claude":
            continue
        usage = entry.get("usage")
        if not isinstance(usage, dict):
            continue
        updated_at = parse_time(usage.get("updatedAt"))
        if updated_at is None or not (dt.timedelta(0) <= now - updated_at <= FRESH_FOR):
            continue
        found_fresh_provider = True
        for window in walk_windows(usage):
            resets_at = parse_time(window.get("resetsAt"))
            observations.append((float(window["usedPercent"]), resets_at))

    return observations if found_fresh_provider else None


def read_state(path: Path) -> dict[str, Any] | None:
    try:
        state = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return state if isinstance(state, dict) else None


def write_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".state.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w") as temporary:
            json.dump(state, temporary, sort_keys=True)
            temporary.write("\n")
            temporary.flush()
            os.fsync(temporary.fileno())
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass


def notify(title: str, body: str) -> None:
    command = os.environ.get("CLAUDE_LIMIT_NOTIFY_SEND", "notify-send")
    try:
        subprocess.run(
            [command, "--app-name=Claude limit watch", title, body],
            check=False,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def focus_only_claude_agent() -> None:
    herdr = os.environ.get("CLAUDE_LIMIT_HERDR", "herdr")
    try:
        result = subprocess.run(
            [herdr, "agent", "list"],
            check=True,
            capture_output=True,
            text=True,
            timeout=10,
        )
        document = json.loads(result.stdout)
        agents = document.get("result", {}).get("agents", [])
        claude_agents = [
            agent
            for agent in agents
            if isinstance(agent, dict) and agent.get("agent") == "claude"
        ]
        if len(claude_agents) != 1:
            return
        target = claude_agents[0].get("pane_id")
        if not isinstance(target, str) or not target:
            return
        subprocess.run(
            [herdr, "agent", "focus", target],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10,
        )
    except (
        OSError,
        subprocess.TimeoutExpired,
        subprocess.CalledProcessError,
        json.JSONDecodeError,
    ):
        pass


def run(usage_file: Path, state_dir: Path, now: dt.datetime) -> None:
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    state_path = state_dir / "state.json"
    lock_path = state_dir / "lock"
    with lock_path.open("a+") as lock:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = read_state(state_path)

        observations = fresh_claude_windows(usage_file, now)
        live = (
            []
            if observations is None
            else [
                (percent, reset)
                for percent, reset in observations
                if reset is not None and reset > now
            ]
        )
        reported_exhausted = (
            []
            if observations is None
            else sorted(
                (
                    (percent, reset)
                    for percent, reset in observations
                    if percent >= 100 and reset is not None
                ),
                key=lambda observation: observation[1],
            )
        )
        if (
            state is not None
            and state.get("phase") == "exhausted"
            and reported_exhausted
        ):
            _, resets_at = reported_exhausted[0]
            if parse_time(state.get("resetsAt")) != resets_at:
                # A reset-time correction while usage remains exhausted is the
                # same episode. Advance its schedule without sending a second
                # exhaustion notification.
                state["resetsAt"] = format_time(resets_at)
                write_state(state_path, state)
            if resets_at > now:
                return

        exhausted = sorted(
            ((percent, reset) for percent, reset in live if percent >= 100),
            key=lambda observation: observation[1],
        )
        if exhausted:
            _, resets_at = exhausted[0]
            same_window = (
                state is not None and parse_time(state.get("resetsAt")) == resets_at
            )
            if same_window and state is not None and state.get("phase") == "reset":
                return
            state = {
                "phase": "exhausted",
                "resetsAt": format_time(resets_at),
                "exhaustedNotifiedAt": format_time(now),
            }
            write_state(state_path, state)
            notify(
                "Claude five-hour limit exhausted",
                f"The limit is scheduled to reset at {format_time(resets_at)}.",
            )
            return

        if state is not None and state.get("phase") == "exhausted":
            scheduled_reset = parse_time(state.get("resetsAt"))
            if scheduled_reset is not None and now >= scheduled_reset:
                state = {
                    "phase": "reset",
                    "resetsAt": format_time(scheduled_reset),
                    "resetNotifiedAt": format_time(now),
                }
                write_state(state_path, state)
                notify(
                    "Claude limit reset",
                    "Claude's five-hour usage window is available again.",
                )
                focus_only_claude_agent()

        if observations is None:
            return

        # A fresh live five-hour window below the limit supersedes exhausted or
        # reset state. Keep no idle state: the next >=100 observation is a new
        # exhaustion transition.
        if any(percent < 100 for percent, _ in observations):
            try:
                state_path.unlink()
            except FileNotFoundError:
                pass


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--usage-file",
        type=Path,
        default=Path.home() / ".cache/codexbar/usage.json",
    )
    parser.add_argument(
        "--state-dir",
        type=Path,
        default=Path(
            os.environ.get(
                "STATE_DIRECTORY", Path.home() / ".local/state/claude-limit-watch"
            )
        ),
    )
    parser.add_argument("--now", help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    now = parse_time(arguments.now) if arguments.now else dt.datetime.now(dt.timezone.utc)
    if now is None:
        parser.error("--now must be an ISO 8601 timestamp with a timezone")
    run(arguments.usage_file, arguments.state_dir, now)


if __name__ == "__main__":
    main()
