#!/usr/bin/env python3
"""Fail-open Codex hook: forward one bounded event to the local coordinator."""

from __future__ import annotations

import json
import os
import socket
import sys


MAX_INPUT = 24 * 1024
MAX_PROMPT = 4_000


def main() -> int:
    try:
        raw = sys.stdin.buffer.read(MAX_INPUT + 1)
        if len(raw) > MAX_INPUT:
            return 0
        incoming = json.loads(raw)
        # Codex includes these fields only for subagents. They must not contend
        # for the enclosing tab's title.
        if incoming.get("agent_id") or incoming.get("agent_type"):
            return 0
        event_name = incoming.get("hook_event_name")
        if event_name not in {"SessionStart", "UserPromptSubmit"}:
            return 0
        event = {
            "version": 1,
            "type": "codex_session" if event_name == "SessionStart" else "codex_prompt",
            "session_id": str(incoming.get("session_id") or "")[:256],
            "turn_id": str(incoming.get("turn_id") or "")[:256],
            "cwd": str(incoming.get("cwd") or os.getcwd())[:4096],
            "source": str(incoming.get("source") or "")[:64],
            "socket": str(os.environ.get("HERDR_SOCKET_PATH") or "")[:4096],
            "pane_id": str(os.environ.get("HERDR_PANE_ID") or "")[:256],
            "tab_id": str(os.environ.get("HERDR_TAB_ID") or "")[:256],
        }
        if event_name == "UserPromptSubmit":
            event["prompt"] = str(incoming.get("prompt") or "")[:MAX_PROMPT]
        runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        target = os.path.join(runtime, "herdr-title", "events.sock")
        payload = json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode()
        client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        try:
            client.settimeout(0.05)
            client.sendto(payload, target)
        finally:
            client.close()
    except Exception:
        # Title delivery is presentation metadata and may never obstruct Codex.
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
