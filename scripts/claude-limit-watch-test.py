#!/usr/bin/env python3
"""Black-box state-machine tests for claude-limit-watch.py."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile


SCRIPT = Path(__file__).with_name("claude-limit-watch.py")


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


def main() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        usage = root / "usage.json"
        state = root / "state"
        log = root / "calls"
        notify = root / "notify"
        herdr = root / "herdr"
        notify.write_text(f"#!/bin/sh\nprintf 'notify %s\\n' \"$*\" >> {log}\n")
        herdr.write_text(
            f'''#!/bin/sh
if [ "$1 $2" = "agent list" ]; then
  printf '%s\\n' '{{"result":{{"agents":[{{"agent":"claude","pane_id":"w1:p2"}}]}}}}'
elif [ "$1 $2" = "agent focus" ]; then
  printf 'focus %s\\n' "$3" >> {log}
fi
'''
        )
        notify.chmod(0o755)
        herdr.chmod(0o755)
        environment = os.environ | {
            "CLAUDE_LIMIT_NOTIFY_SEND": str(notify),
            "CLAUDE_LIMIT_HERDR": str(herdr),
        }

        def run(now: str) -> None:
            subprocess.run(
                [
                    str(SCRIPT),
                    "--usage-file",
                    str(usage),
                    "--state-dir",
                    str(state),
                    "--now",
                    now,
                ],
                check=True,
                env=environment,
            )

        write_usage(usage, "2026-08-13T08:00:00Z", 100, "2026-08-13T10:00:00Z")
        run("2026-08-13T08:16:00Z")
        assert not (state / "state.json").exists(), "stale usage was accepted"

        write_usage(usage, "2026-08-13T08:05:00Z", 100, "2026-08-13T10:00:00Z")
        run("2026-08-13T08:10:00Z")
        run("2026-08-13T08:11:00Z")
        saved = json.loads((state / "state.json").read_text())
        assert saved["phase"] == "exhausted"
        assert log.read_text().count("exhausted") == 1, "exhaustion was notified twice"

        # A backend correction advances the authoritative schedule without
        # starting a second exhaustion episode.
        write_usage(usage, "2026-08-13T08:12:00Z", 100, "2026-08-13T10:30:00Z")
        run("2026-08-13T08:13:00Z")
        saved = json.loads((state / "state.json").read_text())
        assert saved["resetsAt"] == "2026-08-13T10:30:00Z"
        assert log.read_text().count("exhausted") == 1, "reset correction re-notified"

        # The stale cache cannot suppress the authoritative persisted schedule.
        run("2026-08-13T10:30:01Z")
        run("2026-08-13T10:31:00Z")
        saved = json.loads((state / "state.json").read_text())
        assert saved["phase"] == "reset"
        calls = log.read_text()
        assert calls.count("limit reset") == 1, "reset was not notified exactly once"
        assert calls.count("focus w1:p2") == 1, "sole Claude agent was not focused"

        # A fresh lower observation is enough to clear old state even if that
        # window has no usable schedule.
        write_usage(usage, "2026-08-13T10:32:00Z", 12, None)
        run("2026-08-13T10:33:00Z")
        assert not (state / "state.json").exists(), "new lower window did not clear state"

        write_usage(usage, "2026-08-13T10:34:00Z", 100, "2026-08-13T15:00:00Z")
        run("2026-08-13T10:35:00Z")
        assert log.read_text().count("exhausted") == 2, "new window was not observed"

        # A correction that moves the reset into the past is authoritative and
        # transitions immediately instead of waiting for the old schedule.
        write_usage(usage, "2026-08-13T10:36:00Z", 100, "2026-08-13T10:35:30Z")
        run("2026-08-13T10:37:00Z")
        saved = json.loads((state / "state.json").read_text())
        assert saved["phase"] == "reset", "past reset correction was delayed"
        assert log.read_text().count("limit reset") == 2


if __name__ == "__main__":
    main()
