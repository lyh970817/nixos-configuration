#!/usr/bin/env python3
"""Black-box state-machine tests for claude-limit-watch.py."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


SCRIPT = Path(__file__).with_name("claude-limit-watch.py")
PROMPT = (
    "Your five-hour usage limit has reset. Continue the work that was interrupted "
    "by the limit from where you left off. If no work was interrupted, do not start "
    "anything new; reply briefly that no continuation is needed."
)
SESSION_A = "11111111-1111-4111-8111-111111111111"
SESSION_B = "22222222-2222-4222-8222-222222222222"
SESSION_C = "33333333-3333-4333-8333-333333333333"
SESSION_D = "44444444-4444-4444-8444-444444444444"
SESSION_E = "55555555-5555-4555-8555-555555555555"
SESSION_F = "66666666-6666-4666-8666-666666666666"
SESSION_G = "77777777-7777-4777-8777-777777777777"


def write_usage(path: Path, updated: str, percent: int, reset: str | None) -> None:
    path.write_text(
        json.dumps(
            [
                {"provider": "codex", "usage": {"updatedAt": updated}},
                {
                    "provider": "claude",
                    "usage": {
                        "updatedAt": updated,
                        "primary": {
                            "windowMinutes": 300,
                            "usedPercent": percent,
                            "resetsAt": reset,
                        },
                    },
                },
            ]
        )
    )


def agent(
    terminal: str,
    session: str | None,
    pane: str,
    status: str = "idle",
    *,
    detected: str = "claude",
    source: str = "herdr:claude",
    kind: str = "id",
) -> dict[str, object]:
    value: dict[str, object] = {
        "terminal_id": terminal,
        "pane_id": pane,
        "agent": detected,
        "agent_status": status,
    }
    if session is not None:
        value["agent_session"] = {
            "source": source,
            "agent": "claude",
            "kind": kind,
            "value": session,
        }
    return value


class Scenario:
    def __init__(self, root: Path, name: str):
        self.root = root / name
        self.root.mkdir()
        self.usage = self.root / "usage.json"
        self.state = self.root / "state"
        self.listing = self.root / "agents.json"
        self.log = self.root / "calls.jsonl"
        self.herdr = self.root / "herdr"
        self.notify = self.root / "notify"
        fake = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import sys

log = Path(os.environ["HERDR_FAKE_LOG"])
entry = {"tool": Path(sys.argv[0]).name, "args": sys.argv[1:]}
if sys.argv[1:3] == ["agent", "prompt"]:
    state = json.loads(Path(os.environ["HERDR_FAKE_STATE"]).read_text())
    entry["marker"] = any(
        target.get("resumeAttemptedAt") and target.get("resumeResult") == "prompt_attempted"
        for target in state.get("targets", [])
    )
with log.open("a") as handle:
    handle.write(json.dumps(entry) + "\n")

if sys.argv[1:3] == ["agent", "list"]:
    if os.environ.get("HERDR_FAKE_LIST_EXIT"):
        raise SystemExit(int(os.environ["HERDR_FAKE_LIST_EXIT"]))
    sys.stdout.write(Path(os.environ["HERDR_FAKE_LIST"]).read_text())
elif sys.argv[1:3] == ["agent", "prompt"]:
    if os.environ.get("HERDR_FAKE_KILL_WATCHER") == "1":
        os.kill(os.getppid(), signal.SIGKILL)
    raise SystemExit(int(os.environ.get("HERDR_FAKE_PROMPT_EXIT", "0")))
'''
        self.herdr.write_text(fake)
        self.notify.write_text(fake)
        self.herdr.chmod(0o755)
        self.notify.chmod(0o755)
        self.environment = os.environ | {
            "CLAUDE_LIMIT_NOTIFY_SEND": str(self.notify),
            "CLAUDE_LIMIT_HERDR": str(self.herdr),
            "HERDR_FAKE_LIST": str(self.listing),
            "HERDR_FAKE_LOG": str(self.log),
            "HERDR_FAKE_STATE": str(self.state / "state.json"),
        }
        self.set_agents([])

    def set_agents(self, agents: list[dict[str, object]]) -> None:
        self.listing.write_text(json.dumps({"result": {"agents": agents}}))

    def run(self, now: str, **environment: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                str(SCRIPT),
                "--usage-file",
                str(self.usage),
                "--state-dir",
                str(self.state),
                "--now",
                now,
            ],
            check=False,
            env=self.environment | environment,
            text=True,
        )

    def saved(self) -> dict[str, object]:
        return json.loads((self.state / "state.json").read_text())

    def calls(self, tool: str | None = None) -> list[dict[str, object]]:
        if not self.log.exists():
            return []
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return calls if tool is None else [call for call in calls if call["tool"] == tool]

    def prompts(self) -> list[dict[str, object]]:
        return [
            call
            for call in self.calls("herdr")
            if call["args"][:2] == ["agent", "prompt"]
        ]


def test_capture_dedupe_moved_multiple(root: Path) -> None:
    case = Scenario(root, "capture")
    case.set_agents(
        [
            agent("term-b", SESSION_B, "w1:p2"),
            agent("term-a", SESSION_A, "w1:p1"),
            agent("term-a", SESSION_A, "w9:p9"),
            agent("wrong-source", SESSION_C, "w1:p3", source="manual"),
            agent("wrong-kind", SESSION_C, "w1:p4", kind="path"),
            agent("bad-uuid", "not-a-uuid", "w1:p5"),
            agent("not-claude", SESSION_C, "w1:p6", detected="codex"),
        ]
    )
    write_usage(case.usage, "2026-08-13T08:05:00Z", 100, "2026-08-13T10:00:00Z")
    assert case.run("2026-08-13T08:10:00Z").returncode == 0
    saved = case.saved()
    assert saved["version"] == 2
    assert saved["targets"] == [
        {"terminalId": "term-a", "sessionId": SESSION_A, "paneIdAtExhaustion": "w1:p1"},
        {"terminalId": "term-b", "sessionId": SESSION_B, "paneIdAtExhaustion": "w1:p2"},
    ]

    case.set_agents(
        [
            agent("term-a", SESSION_A, "w2:p8", "idle"),
            agent("term-b", SESSION_B, "w3:p7", "done"),
        ]
    )
    assert case.run("2026-08-13T10:00:01Z").returncode == 0
    assert [call["args"] for call in case.prompts()] == [
        ["agent", "prompt", "w2:p8", PROMPT],
        ["agent", "prompt", "w3:p7", PROMPT],
    ]
    assert all(call["marker"] is True for call in case.prompts())
    assert case.saved()["phase"] == "reset"
    assert [target["resumeResult"] for target in case.saved()["targets"]] == [
        "resumed",
        "resumed",
    ]
    case.run("2026-08-13T10:01:00Z")
    assert len(case.prompts()) == 2, "reset rerun prompted again"


def test_skips_and_summary(root: Path) -> None:
    case = Scenario(root, "skips")
    sessions = [SESSION_A, SESSION_B, SESSION_C, SESSION_D, SESSION_E, SESSION_F]
    case.set_agents(
        [agent(f"term-{index}", session, f"w1:p{index}") for index, session in enumerate(sessions)]
    )
    write_usage(case.usage, "2026-08-13T08:00:00Z", 100, "2026-08-13T09:00:00Z")
    case.run("2026-08-13T08:01:00Z")
    case.set_agents(
        [
            agent("term-0", SESSION_A, "w2:p0", "working"),
            agent("term-1", SESSION_B, "w2:p1", "blocked"),
            agent("term-2", SESSION_C, "w2:p2", "unknown"),
            agent("term-3", SESSION_G, "w2:p3", "idle"),
            agent("term-4", None, "w2:p4", "idle"),
            # term-5 is missing; exited sessions must not be auto-launched.
        ]
    )
    case.run("2026-08-13T09:00:01Z")
    assert not case.prompts()
    results = [target["resumeResult"] for target in case.saved()["targets"]]
    assert results == [
        "already_running",
        "blocked",
        "unknown",
        "replaced",
        "identity_absent",
        "missing",
    ]
    calls = case.calls("notify")
    body = " ".join(calls[-1]["args"])
    for label in results:
        assert f"{label}=1" in body
    assert not any(call["args"][:2] == ["agent", "start"] for call in case.calls("herdr"))


def test_malformed_and_list_failure(root: Path) -> None:
    malformed = Scenario(root, "malformed")
    malformed.listing.write_text("not json")
    write_usage(malformed.usage, "2026-08-13T08:00:00Z", 100, "2026-08-13T09:00:00Z")
    malformed.run("2026-08-13T08:01:00Z")
    assert malformed.saved()["targets"] == []

    failure = Scenario(root, "list-failure")
    failure.set_agents([agent("term-a", SESSION_A, "w1:p1")])
    write_usage(failure.usage, "2026-08-13T08:00:00Z", 100, "2026-08-13T09:00:00Z")
    failure.run("2026-08-13T08:01:00Z")
    failure.run("2026-08-13T09:00:01Z", HERDR_FAKE_LIST_EXIT="7")
    assert failure.saved()["targets"][0]["resumeResult"] == "list_failed"
    assert not failure.prompts()
    assert "list_failed=1" in " ".join(failure.calls("notify")[-1]["args"])


def test_correction_lower_and_legacy(root: Path) -> None:
    case = Scenario(root, "correction")
    case.set_agents([agent("term-a", SESSION_A, "w1:p1")])
    write_usage(case.usage, "2026-08-13T08:05:00Z", 100, "2026-08-13T10:00:00Z")
    case.run("2026-08-13T08:10:00Z")
    case.run("2026-08-13T08:11:00Z")
    assert len([call for call in case.calls("notify") if "exhausted" in " ".join(call["args"])]) == 1

    write_usage(case.usage, "2026-08-13T08:12:00Z", 100, "2026-08-13T10:30:00Z")
    case.run("2026-08-13T08:13:00Z")
    assert case.saved()["resetsAt"] == "2026-08-13T10:30:00Z"
    assert case.saved()["targets"][0]["sessionId"] == SESSION_A

    case.set_agents([agent("term-a", SESSION_A, "w2:p2")])
    case.run("2026-08-13T10:30:01Z")
    assert len(case.prompts()) == 1

    write_usage(case.usage, "2026-08-13T10:32:00Z", 12, None)
    case.run("2026-08-13T10:33:00Z")
    assert not (case.state / "state.json").exists(), "lower window did not clear state"

    write_usage(case.usage, "2026-08-13T10:34:00Z", 100, "2026-08-13T15:00:00Z")
    case.run("2026-08-13T10:35:00Z")
    write_usage(case.usage, "2026-08-13T10:36:00Z", 100, "2026-08-13T10:35:30Z")
    case.run("2026-08-13T10:37:00Z")
    assert case.saved()["phase"] == "reset", "past correction was delayed"

    legacy = Scenario(root, "legacy")
    legacy.state.mkdir()
    (legacy.state / "state.json").write_text(
        json.dumps({"phase": "exhausted", "resetsAt": "2026-08-13T09:00:00Z"})
    )
    legacy.usage.write_text("not json")
    legacy.run("2026-08-13T09:01:00Z")
    assert legacy.saved()["version"] == 2
    assert legacy.saved()["phase"] == "reset"
    assert legacy.saved()["targets"] == []
    assert not legacy.prompts()


def test_crash_write_ahead(root: Path) -> None:
    case = Scenario(root, "crash")
    case.set_agents([agent("term-a", SESSION_A, "w1:p1")])
    write_usage(case.usage, "2026-08-13T08:00:00Z", 100, "2026-08-13T09:00:00Z")
    case.run("2026-08-13T08:01:00Z")
    crashed = case.run("2026-08-13T09:00:01Z", HERDR_FAKE_KILL_WATCHER="1")
    assert crashed.returncode != 0
    saved = case.saved()
    assert saved["phase"] == "exhausted"
    assert saved["targets"][0]["resumeAttemptedAt"]
    assert saved["targets"][0]["resumeResult"] == "prompt_attempted"
    assert case.prompts()[0]["marker"] is True

    case.run("2026-08-13T09:01:00Z")
    assert len(case.prompts()) == 1, "ambiguous crashed prompt was retried"
    assert case.saved()["phase"] == "reset"
    assert case.saved()["targets"][0]["resumeResult"] == "prompt_attempted"


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        test_capture_dedupe_moved_multiple(root)
        test_skips_and_summary(root)
        test_malformed_and_list_failure(root)
        test_correction_lower_and_legacy(root)
        test_crash_write_ahead(root)


if __name__ == "__main__":
    main()
