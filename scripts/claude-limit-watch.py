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
import uuid


FRESH_FOR = dt.timedelta(minutes=15)
STATE_VERSION = 2
RESUME_PROMPT = (
    "Your five-hour usage limit has reset. Continue the work that was interrupted "
    "by the limit from where you left off. If no work was interrupted, do not start "
    "anything new; reply briefly that no continuation is needed."
)


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


def migrate_state(state: dict[str, Any] | None) -> tuple[dict[str, Any] | None, bool]:
    if state is None:
        return None, False
    if state.get("version") == STATE_VERSION:
        if not isinstance(state.get("targets"), list):
            state = dict(state)
            state["targets"] = []
            return state, True
        return state, False

    # Version 1 had no explicit version or captured agent identities. It is
    # safe to preserve its schedule, but there is nothing trustworthy to
    # resume after that schedule elapses.
    migrated = dict(state)
    migrated["version"] = STATE_VERSION
    migrated["targets"] = []
    return migrated, True


def list_herdr_agents() -> list[dict[str, Any]] | None:
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
        if not isinstance(document, dict):
            return None
        result_object = document.get("result")
        if not isinstance(result_object, dict):
            return None
        agents = result_object.get("agents")
        if not isinstance(agents, list) or not all(
            isinstance(agent, dict) for agent in agents
        ):
            return None
        return agents
    except (
        OSError,
        subprocess.TimeoutExpired,
        subprocess.CalledProcessError,
        json.JSONDecodeError,
    ):
        return None


def session_uuid(agent: dict[str, Any]) -> str | None:
    identity = agent.get("agent_session")
    if (
        not isinstance(identity, dict)
        or identity.get("source") != "herdr:claude"
        or identity.get("kind") != "id"
    ):
        return None
    value = identity.get("value")
    if not isinstance(value, str) or not value:
        return None
    try:
        return str(uuid.UUID(value))
    except (ValueError, AttributeError):
        return None


def capture_targets() -> list[dict[str, str]]:
    agents = list_herdr_agents()
    if agents is None:
        return []
    captured: dict[tuple[str, str], dict[str, str]] = {}
    for agent in agents:
        terminal_id = agent.get("terminal_id")
        pane_id = agent.get("pane_id")
        session_id = session_uuid(agent)
        if (
            agent.get("agent") != "claude"
            or not isinstance(terminal_id, str)
            or not terminal_id
            or not isinstance(pane_id, str)
            or not pane_id
            or session_id is None
        ):
            continue
        key = (terminal_id, session_id)
        captured.setdefault(
            key,
            {
                "terminalId": terminal_id,
                "sessionId": session_id,
                "paneIdAtExhaustion": pane_id,
            },
        )
    return [captured[key] for key in sorted(captured)]


def resume_summary(targets: list[dict[str, Any]]) -> str:
    counts: dict[str, int] = {}
    for target in targets:
        result = target.get("resumeResult")
        if isinstance(result, str):
            counts[result] = counts.get(result, 0) + 1
    if not targets:
        return "No standard-profile Herdr Claude sessions were captured for continuation."
    ordered = [
        "resumed",
        "already_running",
        "blocked",
        "unknown",
        "missing",
        "replaced",
        "identity_absent",
        "list_failed",
        "prompt_failed",
        "prompt_attempted",
    ]
    parts = [f"{name}={counts[name]}" for name in ordered if counts.get(name)]
    return "Continuation summary: " + ", ".join(parts) + "."


def resume_targets(
    state_path: Path, state: dict[str, Any], now: dt.datetime
) -> dict[str, Any]:
    raw_targets = state.get("targets")
    targets = (
        [target for target in raw_targets if isinstance(target, dict)]
        if isinstance(raw_targets, list)
        else []
    )
    state["targets"] = targets
    agents = list_herdr_agents() if targets else []
    by_terminal: dict[str, dict[str, Any]] = {}
    if agents is not None:
        for agent in agents:
            terminal_id = agent.get("terminal_id")
            if isinstance(terminal_id, str) and terminal_id:
                by_terminal.setdefault(terminal_id, agent)

    for target in targets:
        if isinstance(target.get("resumeResult"), str):
            continue
        if isinstance(target.get("resumeAttemptedAt"), str):
            # A previous process wrote the marker before invoking Herdr. Its
            # outcome is ambiguous, so completing the state must never resend.
            target["resumeResult"] = "prompt_attempted"
            write_state(state_path, state)
            continue

        result: str
        if agents is None:
            result = "list_failed"
        else:
            terminal_id = target.get("terminalId")
            expected_session = target.get("sessionId")
            agent = by_terminal.get(terminal_id) if isinstance(terminal_id, str) else None
            if agent is None:
                result = "missing"
            elif agent.get("agent") != "claude":
                result = "replaced"
            else:
                current_session = session_uuid(agent)
                if current_session is None:
                    result = "identity_absent"
                elif current_session != expected_session:
                    result = "replaced"
                else:
                    status = agent.get("agent_status")
                    if status == "working":
                        result = "already_running"
                    elif status in ("blocked", "unknown"):
                        result = status
                    elif status in ("idle", "done"):
                        pane_id = agent.get("pane_id")
                        if not isinstance(pane_id, str) or not pane_id:
                            result = "missing"
                        else:
                            target["resumeAttemptedAt"] = format_time(now)
                            target["resumeResult"] = "prompt_attempted"
                            write_state(state_path, state)
                            herdr = os.environ.get("CLAUDE_LIMIT_HERDR", "herdr")
                            try:
                                prompt = subprocess.run(
                                    [herdr, "agent", "prompt", pane_id, RESUME_PROMPT],
                                    check=False,
                                    stdout=subprocess.DEVNULL,
                                    stderr=subprocess.DEVNULL,
                                    timeout=10,
                                )
                                result = "resumed" if prompt.returncode == 0 else "prompt_failed"
                            except (OSError, subprocess.TimeoutExpired):
                                result = "prompt_failed"
                            target["resumeResult"] = result
                            write_state(state_path, state)
                            continue
                    else:
                        result = "unknown"
        target["resumeResult"] = result
        target["resumeEvaluatedAt"] = format_time(now)
        write_state(state_path, state)

    state["phase"] = "reset"
    state["resetNotifiedAt"] = format_time(now)
    write_state(state_path, state)
    notify(
        "Claude limit reset",
        "Claude's five-hour usage window is available again. " + resume_summary(targets),
    )
    return state


def run(usage_file: Path, state_dir: Path, now: dt.datetime) -> None:
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    state_path = state_dir / "state.json"
    lock_path = state_dir / "lock"
    with lock_path.open("a+") as lock:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        state, migrated = migrate_state(read_state(state_path))
        if migrated and state is not None:
            write_state(state_path, state)

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
                "version": STATE_VERSION,
                "phase": "exhausted",
                "resetsAt": format_time(resets_at),
                "exhaustedNotifiedAt": format_time(now),
                "targets": capture_targets(),
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
                resume_targets(state_path, state, now)

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
