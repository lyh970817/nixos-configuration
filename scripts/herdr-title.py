#!/usr/bin/env python3
"""Coordinate semantic titles across all local Herdr 0.8 sessions."""

from __future__ import annotations

import argparse
import asyncio
import collections
import contextlib
import json
import os
import re
import socket
import stat
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


SUBSCRIPTIONS = [
    "tab.created", "tab.closed", "tab.renamed", "tab.moved",
    "pane.created", "pane.closed", "pane.updated", "pane.moved",
    "pane.exited", "pane.agent_detected", "pane.agent_status_changed",
]
MAX_TITLE = 64
OWNER_RESTART_GRACE = 5.0


def clean_title(value: Any, maximum: int = MAX_TITLE) -> str:
    text = str(value or "").replace("\n", " ").replace("\r", " ").replace("\t", " ").replace("\x1b", "")
    text = " ".join("".join("" if unicodedata_category(ch) == "C" else ch for ch in text).split())
    return text[:maximum].strip()


def unicodedata_category(ch: str) -> str:
    import unicodedata
    return unicodedata.category(ch)[0]


class JsonState:
    def __init__(self, path: Path):
        self.path = path
        self.data: dict[str, Any] = {"version": 1, "servers": {}, "tabs": {}}
        try:
            loaded = json.loads(path.read_text())
            if loaded.get("version") == 1 and isinstance(loaded.get("tabs"), dict):
                self.data = loaded
        except (OSError, ValueError, TypeError):
            pass
        self.data.setdefault("servers", {})

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
        self.coordinator.confirm_incarnation(self)
        self.snapshot = result.get("snapshot", {})
        await self.coordinator.reconcile(self)

    def incarnation(self) -> list[int]:
        info = os.stat(self.socket_path, follow_symlinks=False)
        if not stat.S_ISSOCK(info.st_mode):
            raise ValueError("Herdr API path is not a socket")
        return [info.st_dev, info.st_ino, info.st_ctime_ns]

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
    def __init__(self, config_home: Path, runtime: Path, state_home: Path):
        self.config_home = config_home
        self.runtime = runtime
        self.state = JsonState(state_home / "herdr-title" / "state.json")
        self.connections: dict[str, HerdrConnection] = {}
        self.tasks: dict[str, asyncio.Task[Any]] = {}
        self.owner_grace_handles: dict[str, asyncio.TimerHandle] = {}

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
                self.cancel_socket_owner_rechecks(socket_path)
            await asyncio.sleep(2)

    def confirm_incarnation(self, connection: HerdrConnection) -> None:
        socket_path = connection.socket_path
        incarnation = connection.incarnation()
        previous = self.state.data["servers"].get(socket_path)
        if previous is not None and previous != incarnation:
            self.cancel_socket_owner_rechecks(socket_path)
            prefix = f"{socket_path}\0"
            for key in [key for key in self.state.data["tabs"] if key.startswith(prefix)]:
                self.state.data["tabs"].pop(key, None)
        self.state.data["servers"][socket_path] = incarnation
        self.state.save()

    def cancel_socket_owner_rechecks(self, socket_path: str) -> None:
        prefix = f"{socket_path}\0"
        for key in [key for key in self.owner_grace_handles if key.startswith(prefix)]:
            self.owner_grace_handles.pop(key).cancel()

    def schedule_owner_recheck(self, connection: HerdrConnection, tab_id: str, delay: float) -> None:
        key = self.tab_key(connection.socket_path, tab_id)
        if key in self.owner_grace_handles:
            return

        async def refresh() -> None:
            try:
                await connection.refresh_snapshot()
            except Exception:
                pass

        def trigger() -> None:
            self.owner_grace_handles.pop(key, None)
            asyncio.create_task(refresh())

        self.owner_grace_handles[key] = asyncio.get_running_loop().call_later(max(0.0, delay), trigger)

    def cancel_owner_recheck(self, socket_path: str, tab_id: str) -> None:
        key = self.tab_key(socket_path, tab_id)
        if handle := self.owner_grace_handles.pop(key, None):
            handle.cancel()

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
                self.cancel_owner_recheck(connection.socket_path, tab_id)
        for tab_id, tab in tabs.items():
            state_key = f"{connection.socket_path}\0{tab_id}"
            state_existed = state_key in self.state.data["tabs"]
            state = self.state.tab(connection.socket_path, tab_id)
            # Read the label back at the same 256-character limit `rename` writes
            # and records. Clamping to MAX_TITLE here instead truncated every
            # label longer than 64 characters, so it never matched the recorded
            # title and the tab was misread as an offline manual rename.
            label = clean_title(tab.get("label"), 256)
            positional_label = bool(label and re.fullmatch(r"[0-9]+", label))
            recovered_numeric_pin = False
            if (
                state.get("pinned")
                and positional_label
                and clean_title(state.get("title"), 256) == label
            ):
                # Numeric labels are Herdr positions, never durable manual
                # topics. Recover state pinned by an older reconciliation race
                # so a new Codex session cannot remain frozen at (for example)
                # `1` forever.
                state.pop("pinned", None)
                recovered_numeric_pin = True
            if not state_existed and label and not re.fullmatch(r"[0-9]+", label):
                # With no automatic-title baseline, a semantic label already
                # present in Herdr is user-owned. Preserve it on first install
                # and after state loss. Herdr's visible positional labels can
                # differ from its internal number, but always use ASCII digits.
                state.update({"pinned": True, "title": label})
            elif state and state.get("title") and label != state.get("title"):
                expected = getattr(connection, "expected_renames", collections.Counter())
                if expected[(tab_id, label)] == 0:
                    state.update({"pinned": True, "title": label})
            owner = next((p for p in by_tab[tab_id] if p.get("pane_id") == state.get("owner_pane")), None)
            owner_reserved = False
            if owner and not self.owner_kind(owner):
                now = time.time()
                since = float(state.setdefault("owner_ineligible_since", now))
                remaining = OWNER_RESTART_GRACE - (now - since)
                if remaining > 0:
                    owner_reserved = True
                    self.schedule_owner_recheck(connection, tab_id, remaining)
                else:
                    self.cancel_owner_recheck(connection.socket_path, tab_id)
                    for field in ("owner_pane", "owner_kind", "owner_ineligible_since", "session_id"):
                        state.pop(field, None)
                    state["epoch"] = int(state.get("epoch", 0)) + 1
                    owner = None
            elif owner:
                state.pop("owner_ineligible_since", None)
                self.cancel_owner_recheck(connection.socket_path, tab_id)
            if owner is None:
                eligible = [p for p in by_tab[tab_id] if self.owner_kind(p)]
                owner = eligible[0] if eligible else None
                if owner:
                    state.update({"owner_pane": owner["pane_id"], "owner_kind": self.owner_kind(owner), "epoch": int(state.get("epoch", 0)) + 1})
            if owner and not owner_reserved and not state.get("pinned"):
                kind = self.owner_kind(owner)
                state["owner_kind"] = kind
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
                # Herdr can publish this event before the tab.rename response.
                # Advance the automatic baseline now so a concurrent snapshot
                # cannot misclassify our own label as an offline manual rename.
                state = self.state.tab(connection.socket_path, tab_id)
                state["title"] = label
                self.state.save()
            else:
                state = self.state.tab(connection.socket_path, tab_id)
                state.update({"pinned": True, "title": label})
                self.state.save()
        # A snapshot is the authoritative reconciliation surface for all event
        # shapes, including moves that replace opaque pane IDs.
        if event in {"pane.updated", "pane.created", "pane.closed", "pane.moved", "pane.exited", "pane.agent_detected", "pane.agent_status_changed", "tab.created", "tab.closed", "tab.moved"}:
            with contextlib.suppress(Exception):
                await connection.refresh_snapshot()

    async def handle_datagram(self, data: bytes) -> None:
        try:
            event = json.loads(data)
            if event.get("version") != 1:
                return
            if event.get("type") in {"auto", "claim"}:
                await self.handle_control(event)
        except Exception:
            return

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

    def tab_key(self, socket_path: str, tab_id: str) -> str:
        return f"{socket_path}\0{tab_id}"

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
    asyncio.run(Coordinator(config, runtime, state).run())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
