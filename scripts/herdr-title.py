#!/usr/bin/env python3
"""Coordinate semantic titles across all local Herdr 0.8 sessions."""

from __future__ import annotations

import argparse
import asyncio
import collections
import contextlib
import datetime as dt
import json
import os
import re
import socket
import stat
import struct
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


SUBSCRIPTIONS = [
    "tab.created", "tab.closed", "tab.renamed", "tab.moved",
    "pane.created", "pane.closed", "pane.updated", "pane.moved",
    "pane.exited", "pane.agent_detected", "pane.agent_status_changed",
]
MODEL = "qwen3.6-flash"
DEFAULT_ENDPOINT = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
MAX_PROMPT = 1_000
MAX_TITLE = 64
ACKS = {"ok", "okay", "yes", "yep", "sure", "continue", "go ahead", "thanks", "thank you"}
SECRET_PATTERNS = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----", re.I),
    re.compile(r"\b(?:[A-Za-z_][A-Za-z0-9_]*[_-])?(?:api[_-]?key|access[_-]?key|token|secret|password|passwd)[A-Za-z0-9_]*\s*[:=]\s*['\"]?[A-Za-z0-9_./+\-=]{12,}", re.I),
    re.compile(r"\bBearer\s+[A-Za-z0-9_.~+/=-]{12,}", re.I),
    re.compile(r"\b(?:sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}|glpat-[A-Za-z0-9_-]{16,}|xox[baprs]-[A-Za-z0-9-]{16,})\b", re.I),
]


def clean_title(value: Any, maximum: int = MAX_TITLE) -> str:
    text = str(value or "").replace("\n", " ").replace("\r", " ").replace("\t", " ").replace("\x1b", "")
    text = " ".join("".join("" if unicodedata_category(ch) == "C" else ch for ch in text).split())
    return text[:maximum].strip()


def unicodedata_category(ch: str) -> str:
    import unicodedata
    return unicodedata.category(ch)[0]


def fallback_title(cwd: str) -> str:
    name = Path(cwd or "").name or "session"
    return clean_title(f"Codex — {name}")


def is_substantive(prompt: str) -> bool:
    normalized = " ".join(prompt.lower().split()).strip(" .!?")
    return len(normalized) >= 12 and normalized not in ACKS


def contains_secret(prompt: str) -> bool:
    return any(pattern.search(prompt) for pattern in SECRET_PATTERNS)


def local_prompt_title(prompt: str, cwd: str) -> str:
    if contains_secret(prompt):
        return fallback_title(cwd)
    first = next((line.strip(" #*-\t") for line in prompt.splitlines() if line.strip()), "")
    first = re.sub(r"^(?:please\s+|can you\s+|could you\s+|would you\s+)", "", first, flags=re.I)
    return clean_title(first) or fallback_title(cwd)


class JsonState:
    def __init__(self, path: Path):
        self.path = path
        self.data: dict[str, Any] = {"version": 1, "tabs": {}}
        try:
            loaded = json.loads(path.read_text())
            if loaded.get("version") == 1 and isinstance(loaded.get("tabs"), dict):
                self.data = loaded
        except (OSError, ValueError, TypeError):
            pass

    def tab(self, socket_path: str, tab_id: str) -> dict[str, Any]:
        return self.data["tabs"].setdefault(f"{socket_path}\0{tab_id}", {})

    def remove(self, socket_path: str, tab_id: str) -> None:
        self.data["tabs"].pop(f"{socket_path}\0{tab_id}", None)

    def save(self) -> None:
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".state.", dir=self.path.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "w") as out:
                json.dump(self.data, out, ensure_ascii=False, separators=(",", ":"))
                out.write("\n")
            os.replace(temporary, self.path)
        finally:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(temporary)


class HerdrConnection:
    def __init__(self, coordinator: "Coordinator", socket_path: Path):
        self.coordinator = coordinator
        self.socket_path = str(socket_path)
        self.snapshot: dict[str, Any] = {"tabs": [], "panes": []}
        self.expected_renames: collections.Counter[tuple[str, str]] = collections.Counter()

    async def request(self, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        reader, writer = await asyncio.wait_for(asyncio.open_unix_connection(self.socket_path), 1)
        try:
            request_id = f"title-{time.monotonic_ns()}"
            body = {"id": request_id, "method": method, "params": params or {}}
            writer.write(json.dumps(body, separators=(",", ":")).encode() + b"\n")
            await writer.drain()
            line = await asyncio.wait_for(reader.readline(), 1)
            value = json.loads(line)
            if value.get("error"):
                raise RuntimeError("Herdr request failed")
            return value.get("result", {})
        finally:
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()

    async def rename(self, tab_id: str, title: str) -> None:
        title = clean_title(title, 256)
        if not title:
            return
        state = self.coordinator.state.tab(self.socket_path, tab_id)
        if state.get("pinned") or state.get("title") == title:
            return
        self.expected_renames[(tab_id, title)] += 1
        try:
            await self.request("tab.rename", {"tab_id": tab_id, "label": title})
        except Exception:
            self.expected_renames[(tab_id, title)] -= 1
            return
        state["title"] = title
        self.coordinator.state.save()
        asyncio.get_running_loop().call_later(2, lambda: self.expected_renames.pop((tab_id, title), None))

    async def refresh_snapshot(self) -> None:
        result = await self.request("session.snapshot")
        self.snapshot = result.get("snapshot", {})
        await self.coordinator.reconcile(self)

    async def run(self) -> None:
        while True:
            try:
                await self.refresh_snapshot()
                reader, writer = await asyncio.open_unix_connection(self.socket_path)
                body = {
                    "id": "title-subscription",
                    "method": "events.subscribe",
                    "params": {"subscriptions": [{"type": kind} for kind in SUBSCRIPTIONS]},
                }
                writer.write(json.dumps(body, separators=(",", ":")).encode() + b"\n")
                await writer.drain()
                ack = json.loads(await asyncio.wait_for(reader.readline(), 1))
                if ack.get("result", {}).get("type") != "subscription_started":
                    raise RuntimeError("subscription rejected")
                while line := await reader.readline():
                    await self.coordinator.handle_herdr_event(self, json.loads(line))
                writer.close()
                with contextlib.suppress(Exception):
                    await writer.wait_closed()
            except asyncio.CancelledError:
                raise
            except Exception:
                await asyncio.sleep(1)


class DatagramProtocol(asyncio.DatagramProtocol):
    def __init__(self, coordinator: "Coordinator"):
        self.coordinator = coordinator

    def datagram_received(self, data: bytes, _addr: Any) -> None:
        if len(data) <= 32 * 1024:
            asyncio.create_task(self.coordinator.handle_datagram(data))


class Coordinator:
    def __init__(self, config_home: Path, runtime: Path, state_home: Path, credential: Path):
        self.config_home = config_home
        self.runtime = runtime
        self.credential = credential
        self.state = JsonState(state_home / "herdr-title" / "state.json")
        self.connections: dict[str, HerdrConnection] = {}
        self.tasks: dict[str, asyncio.Task[Any]] = {}
        self.generations: dict[str, asyncio.Task[Any]] = {}
        self.generation_pending: dict[str, tuple[Any, ...]] = {}
        self.prompt_seq: collections.Counter[str] = collections.Counter()
        self.requests: collections.deque[float] = collections.deque()
        self.daily: collections.Counter[str] = collections.Counter()
        self.failures = 0
        self.circuit_until = 0.0

    def discover(self) -> list[Path]:
        root = self.config_home / "herdr"
        candidates = [root / "herdr.sock", *root.glob("sessions/*/herdr.sock")]
        result = []
        for path in candidates:
            try:
                mode = path.stat().st_mode
                if stat.S_ISSOCK(mode) and path.owner() == Path.home().owner():
                    result.append(path)
            except OSError:
                continue
        return result

    async def discovery_loop(self) -> None:
        while True:
            found = {str(path): path for path in self.discover()}
            for socket_path, path in found.items():
                if socket_path not in self.tasks:
                    connection = HerdrConnection(self, path)
                    self.connections[socket_path] = connection
                    self.tasks[socket_path] = asyncio.create_task(connection.run())
            for socket_path in set(self.tasks) - set(found):
                self.tasks.pop(socket_path).cancel()
                self.connections.pop(socket_path, None)
            await asyncio.sleep(2)

    @staticmethod
    def owner_kind(pane: dict[str, Any]) -> str | None:
        agent = str(pane.get("agent") or pane.get("display_agent") or "").lower()
        if "claude" in agent:
            return "claude"
        if "codex" in agent:
            return "codex"
        return None

    async def reconcile(self, connection: HerdrConnection) -> None:
        tabs = {tab["tab_id"]: tab for tab in connection.snapshot.get("tabs", [])}
        panes = connection.snapshot.get("panes", [])
        by_tab: dict[str, list[dict[str, Any]]] = collections.defaultdict(list)
        for pane in panes:
            by_tab[pane.get("tab_id", "")].append(pane)
        for key in list(self.state.data["tabs"]):
            socket_path, _, tab_id = key.partition("\0")
            if socket_path == connection.socket_path and tab_id not in tabs:
                self.state.data["tabs"].pop(key, None)
        for tab_id, tab in tabs.items():
            state = self.state.tab(connection.socket_path, tab_id)
            label = clean_title(tab.get("label"))
            if state and state.get("title") and label != state.get("title"):
                expected = getattr(connection, "expected_renames", collections.Counter())
                if expected[(tab_id, label)] == 0:
                    state.update({"pinned": True, "title": label})
                    self.cancel_generation(connection.socket_path, tab_id)
            owner = next((p for p in by_tab[tab_id] if p.get("pane_id") == state.get("owner_pane")), None)
            if owner is None:
                eligible = [p for p in by_tab[tab_id] if self.owner_kind(p)]
                owner = eligible[0] if eligible else None
                if owner:
                    state.update({"owner_pane": owner["pane_id"], "owner_kind": self.owner_kind(owner), "epoch": int(state.get("epoch", 0)) + 1})
            if owner and not state.get("pinned"):
                kind = self.owner_kind(owner) or state.get("owner_kind")
                state["owner_kind"] = kind
                if kind == "claude":
                    title = clean_title(owner.get("terminal_title_stripped"), 256)
                    if title:
                        await connection.rename(tab_id, title)
            state.setdefault("title", label)
        self.state.save()

    async def handle_herdr_event(self, connection: HerdrConnection, message: dict[str, Any]) -> None:
        event = message.get("event")
        data = message.get("data", {})
        if event == "tab.renamed":
            tab_id, label = data.get("tab_id", ""), clean_title(data.get("label"), 256)
            expected = (tab_id, label)
            if connection.expected_renames[expected] > 0:
                connection.expected_renames[expected] -= 1
            else:
                state = self.state.tab(connection.socket_path, tab_id)
                state.update({"pinned": True, "title": label})
                self.cancel_generation(connection.socket_path, tab_id)
                self.state.save()
        # A snapshot is the authoritative reconciliation surface for all event
        # shapes, including moves that replace opaque pane IDs.
        if event in {"pane.updated", "pane.created", "pane.closed", "pane.moved", "pane.exited", "pane.agent_detected", "pane.agent_status_changed", "tab.created", "tab.closed", "tab.moved"}:
            with contextlib.suppress(Exception):
                await connection.refresh_snapshot()

    def find_pane(self, socket_path: str, pane_id: str) -> tuple[HerdrConnection, dict[str, Any]] | None:
        connection = self.connections.get(socket_path)
        if not connection:
            return None
        pane = next((p for p in connection.snapshot.get("panes", []) if p.get("pane_id") == pane_id), None)
        return (connection, pane) if pane else None

    async def handle_datagram(self, data: bytes) -> None:
        try:
            event = self.decode_datagram(data)
            if event.get("version") != 1:
                return
            if event.get("type") in {"auto", "claim"}:
                await self.handle_control(event)
                return
            socket_path, pane_id = str(event.get("socket") or ""), str(event.get("pane_id") or "")
            found = self.find_pane(socket_path, pane_id)
            if not found and socket_path in {str(path) for path in self.discover()}:
                connection = self.connections.get(socket_path) or HerdrConnection(self, Path(socket_path))
                self.connections[socket_path] = connection
                await connection.refresh_snapshot()
                found = self.find_pane(socket_path, pane_id)
            if not found:
                return
            connection, pane = found
            tab_id = pane.get("tab_id")
            state = self.state.tab(socket_path, tab_id)
            owner = state.get("owner_pane")
            if owner and owner != pane_id:
                return
            if not owner:
                state.update({"owner_pane": pane_id, "owner_kind": "codex", "epoch": int(state.get("epoch", 0)) + 1})
            session_id = str(event.get("session_id") or "")
            if not session_id:
                return
            if state.get("session_id") != session_id:
                state.update({"session_id": session_id, "epoch": int(state.get("epoch", 0)) + 1})
                self.cancel_generation(socket_path, tab_id)
                await connection.rename(tab_id, fallback_title(str(event.get("cwd") or pane.get("cwd") or "")))
            self.state.save()
            if event.get("type") == "codex_prompt":
                prompt = str(event.get("prompt") or "")[:MAX_PROMPT]
                if is_substantive(prompt):
                    self.schedule_generation(connection, tab_id, pane_id, session_id, prompt, str(event.get("cwd") or ""))
        except Exception:
            return

    @staticmethod
    def decode_datagram(data: bytes) -> dict[str, Any]:
        if not data.startswith(b"HT1\0"):
            return json.loads(data)
        if len(data) < 20:
            raise ValueError("short hook datagram")
        lengths = struct.unpack("!IIII", data[4:20])
        if any(length > 24 * 1024 for length in lengths) or sum(lengths) != len(data) - 20:
            raise ValueError("invalid hook datagram lengths")
        fields = []
        offset = 20
        for length in lengths:
            fields.append(data[offset:offset + length])
            offset += length
        socket_path, pane_id, tab_id = (field.decode() for field in fields[:3])
        incoming = json.loads(fields[3])
        if incoming.get("agent_id") or incoming.get("agent_type"):
            return {"version": 0}
        name = incoming.get("hook_event_name")
        if name not in {"SessionStart", "UserPromptSubmit"}:
            return {"version": 0}
        event = {
            "version": 1,
            "type": "codex_session" if name == "SessionStart" else "codex_prompt",
            "session_id": str(incoming.get("session_id") or "")[:256],
            "turn_id": str(incoming.get("turn_id") or "")[:256],
            "cwd": str(incoming.get("cwd") or "")[:4096],
            "source": str(incoming.get("source") or "")[:64],
            "socket": socket_path[:4096], "pane_id": pane_id[:256], "tab_id": tab_id[:256],
        }
        if name == "UserPromptSubmit":
            event["prompt"] = str(incoming.get("prompt") or "")[:4_000]
        return event

    async def handle_control(self, event: dict[str, Any]) -> None:
        socket_path, tab_id = str(event.get("socket") or ""), str(event.get("tab_id") or "")
        connection = self.connections.get(socket_path)
        if not connection or not tab_id:
            return
        state = self.state.tab(socket_path, tab_id)
        state["pinned"] = False
        if event.get("type") == "claim":
            pane_id = str(event.get("pane_id") or "")
            pane = next((p for p in connection.snapshot.get("panes", []) if p.get("pane_id") == pane_id and p.get("tab_id") == tab_id), None)
            if pane and self.owner_kind(pane):
                state.update({"owner_pane": pane_id, "owner_kind": self.owner_kind(pane), "epoch": int(state.get("epoch", 0)) + 1})
        self.state.save()
        await connection.refresh_snapshot()

    def generation_key(self, socket_path: str, tab_id: str) -> str:
        return f"{socket_path}\0{tab_id}"

    def cancel_generation(self, socket_path: str, tab_id: str) -> None:
        key = self.generation_key(socket_path, tab_id)
        self.prompt_seq[key] += 1
        self.generation_pending.pop(key, None)

    def schedule_generation(self, connection: HerdrConnection, tab_id: str, pane_id: str, session_id: str, prompt: str, cwd: str) -> None:
        key = self.generation_key(connection.socket_path, tab_id)
        self.prompt_seq[key] += 1
        seq = self.prompt_seq[key]
        epoch = int(self.state.tab(connection.socket_path, tab_id).get("epoch", 0))
        self.generation_pending[key] = (connection, tab_id, pane_id, session_id, epoch, seq, prompt, cwd)
        if key not in self.generations or self.generations[key].done():
            self.generations[key] = asyncio.create_task(self.generation_worker(key))

    async def generation_worker(self, key: str) -> None:
        try:
            while key in self.generation_pending:
                await asyncio.sleep(0.25)
                item = self.generation_pending.get(key)
                if not item:
                    return
                connection, tab_id, pane_id, session_id, epoch, seq, prompt, cwd = item
                prior = str(self.state.tab(connection.socket_path, tab_id).get("title") or "")
                title = local_prompt_title(prompt, cwd) if contains_secret(prompt) else await self.qwen_title(prompt, prior, cwd)
                state = self.state.tab(connection.socket_path, tab_id)
                current = self.find_pane(connection.socket_path, pane_id)
                still_latest = self.generation_pending.get(key) == item and self.prompt_seq[key] == seq
                if still_latest:
                    if current and current[1].get("tab_id") == tab_id:
                        if not state.get("pinned") and state.get("session_id") == session_id and int(state.get("epoch", 0)) == epoch:
                            await connection.rename(tab_id, title)
                    # A completed newest request is consumed even if its pane
                    # closed or moved while HTTP was in flight. Its stale
                    # result is discarded instead of being generated again.
                    self.generation_pending.pop(key, None)
        except asyncio.CancelledError:
            raise
        except Exception:
            return
        finally:
            if self.generations.get(key) is asyncio.current_task():
                self.generations.pop(key, None)

    def allow_request(self) -> bool:
        now = time.monotonic()
        if now < self.circuit_until:
            return False
        while self.requests and self.requests[0] < now - 60:
            self.requests.popleft()
        day = dt.date.today().isoformat()
        if len(self.requests) >= 30 or self.daily[day] >= 500:
            return False
        self.requests.append(now)
        self.daily[day] += 1
        for old_day in list(self.daily):
            if old_day != day:
                del self.daily[old_day]
        return True

    def read_key(self) -> str:
        mode = stat.S_IMODE(self.credential.stat().st_mode)
        if mode & 0o077:
            raise PermissionError("credential permissions are too broad")
        value = json.loads(self.credential.read_text()).get("dashscope")
        if not isinstance(value, str) or not value:
            raise ValueError("credential is missing dashscope")
        return value

    async def qwen_title(self, prompt: str, prior: str, cwd: str) -> str:
        if not self.allow_request():
            return local_prompt_title(prompt, cwd)
        try:
            title = await asyncio.wait_for(asyncio.to_thread(self.qwen_title_sync, prompt[:MAX_PROMPT], prior), 4)
            self.failures = 0
            return title
        except Exception:
            self.failures += 1
            if self.failures >= 5:
                self.circuit_until = time.monotonic() + 600
            return local_prompt_title(prompt, cwd)

    def qwen_title_sync(self, prompt: str, prior: str) -> str:
        body = {
            "model": MODEL,
            "messages": [
                {"role": "system", "content": "Name this coding task in 2-8 plain words. Output only one title line, at most 64 characters. No quotes or punctuation."},
                {"role": "user", "content": f"Prior title: {prior[:MAX_TITLE]}\nCurrent prompt: {prompt[:MAX_PROMPT]}"},
            ],
            "enable_thinking": False,
            "max_completion_tokens": 16,
        }
        request = urllib.request.Request(
            os.environ.get("HERDR_TITLE_QWEN_ENDPOINT", DEFAULT_ENDPOINT),
            data=json.dumps(body, ensure_ascii=False).encode(),
            headers={"Authorization": f"Bearer {self.read_key()}", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=4) as response:
            result = json.load(response)
        candidate = str(result["choices"][0]["message"]["content"])
        title = clean_title(candidate.strip(" '\"`#*-"))
        words = title.split()
        if "\n" in candidate or not 2 <= len(words) <= 8 or len(title) > MAX_TITLE:
            raise ValueError("invalid generated title")
        return title

    async def run(self) -> None:
        self.runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.runtime, 0o700)
        datagram = self.runtime / "events.sock"
        with contextlib.suppress(FileNotFoundError):
            datagram.unlink()
        loop = asyncio.get_running_loop()
        transport, _ = await loop.create_datagram_endpoint(lambda: DatagramProtocol(self), local_addr=str(datagram), family=socket.AF_UNIX)
        os.chmod(datagram, 0o600)
        try:
            await self.discovery_loop()
        finally:
            transport.close()
            with contextlib.suppress(FileNotFoundError):
                datagram.unlink()


def send_control(action: str) -> int:
    if os.environ.get("HERDR_ENV") != "1":
        print("herdr-title: not inside a Herdr pane", file=sys.stderr)
        return 2
    event = {
        "version": 1, "type": action,
        "socket": os.environ.get("HERDR_SOCKET_PATH", ""),
        "pane_id": os.environ.get("HERDR_PANE_ID", ""),
        "tab_id": os.environ.get("HERDR_TAB_ID", ""),
    }
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "herdr-title" / "events.sock"
    try:
        client = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        client.settimeout(0.05)
        client.sendto(json.dumps(event, separators=(",", ":")).encode(), str(runtime))
        client.close()
    except OSError:
        print("herdr-title: coordinator unavailable", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("daemon")
    for action in ("auto", "claim"):
        command = sub.add_parser(action)
        command.add_argument("--current", action="store_true", required=True)
    args = parser.parse_args()
    if args.command in {"auto", "claim"}:
        return send_control(args.command)
    home = Path.home()
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "herdr-title"
    config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config")
    state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
    credential = Path(os.environ.get("HERDR_TITLE_CREDENTIALS") or home / ".local/share/hyprwhspr/credentials")
    asyncio.run(Coordinator(config, runtime, state, credential).run())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
