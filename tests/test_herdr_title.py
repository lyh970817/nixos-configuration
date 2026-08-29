#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import collections
import importlib.util
import json
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("herdr_title", ROOT / "scripts/herdr-title.py")
assert SPEC and SPEC.loader
TITLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TITLE)


def pane(pane_id="w1:p1", agent="codex", title=None):
    return {
        "pane_id": pane_id, "tab_id": "w1:t1", "workspace_id": "w1",
        "terminal_id": pane_id, "agent": agent, "display_agent": agent,
        "terminal_title_stripped": title, "cwd": "/tmp/project",
        "agent_status": "working", "focused": True, "revision": 1,
    }


def tab(label="1", count=1):
    return {
        "tab_id": "w1:t1", "workspace_id": "w1", "number": 1,
        "label": label, "focused": True, "pane_count": count,
        "agent_status": "working",
    }


class FakeConnection:
    def __init__(self, coordinator, panes, tabs=None, socket_path="/fake/herdr.sock"):
        self.coordinator = coordinator
        self.socket_path = socket_path
        self.snapshot = {"panes": panes, "tabs": tabs or [tab()]}
        self.refreshed_panes = None
        self.renames = []
        self.expected_renames = collections.Counter()
        self.identity = [1, 100, 1000]

    def incarnation(self):
        return self.identity

    async def rename(self, tab_id, title):
        state = self.coordinator.state.tab(self.socket_path, tab_id)
        if not state.get("pinned"):
            self.renames.append((tab_id, title))
            state["title"] = title
            for item in self.snapshot["tabs"]:
                if item["tab_id"] == tab_id:
                    item["label"] = title

    async def refresh_snapshot(self):
        if self.refreshed_panes is not None:
            self.snapshot["panes"] = self.refreshed_panes
            self.refreshed_panes = None
        await self.coordinator.reconcile(self)


class HerdrTitleTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.coordinator = TITLE.Coordinator(root / "config", root / "runtime", root / "state")

    async def asyncTearDown(self):
        self.tmp.cleanup()

    async def test_agent_titles_mirror_exact_sanitized_value(self):
        for agent in ("claude", "codex"):
            connection = FakeConnection(self.coordinator, [pane(agent=agent, title="  Native\n\x1bTopic  ")], socket_path=f"/fake/{agent}.sock")
            await self.coordinator.reconcile(connection)
            self.assertEqual(connection.renames, [("w1:t1", "Native Topic")])

    async def test_codex_title_is_not_limited_to_old_qwen_length(self):
        value = "A" * 80
        connection = FakeConnection(self.coordinator, [pane(title=value)])
        await self.coordinator.reconcile(connection)
        self.assertEqual(connection.renames, [("w1:t1", value)])

    async def test_empty_codex_title_does_not_rename(self):
        connection = FakeConnection(self.coordinator, [pane()])
        await self.coordinator.reconcile(connection)
        self.assertEqual(connection.renames, [])

    async def test_initial_manual_label_blocks_native_title(self):
        connection = FakeConnection(self.coordinator, [pane(title="Native Topic")], [tab("Manual Topic")])
        await self.coordinator.reconcile(connection)
        self.assertTrue(self.coordinator.state.tab(connection.socket_path, "w1:t1")["pinned"])
        self.assertEqual(connection.renames, [])

    async def test_numeric_pin_recovers_to_native_title(self):
        connection = FakeConnection(self.coordinator, [pane(title="Native Topic")])
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        state.update({"pinned": True, "title": "1", "owner_pane": "w1:p1", "owner_kind": "codex"})
        await self.coordinator.reconcile(connection)
        self.assertFalse(state.get("pinned", False))
        self.assertEqual(connection.renames, [("w1:t1", "Native Topic")])

    async def test_semantic_pin_remains_manual(self):
        connection = FakeConnection(self.coordinator, [pane(title="Native Topic")], [tab("Manual Topic")])
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        state.update({"pinned": True, "title": "Manual Topic", "owner_pane": "w1:p1", "owner_kind": "codex"})
        await self.coordinator.reconcile(connection)
        self.assertTrue(state["pinned"])
        self.assertEqual(connection.renames, [])

    async def test_only_ascii_numeric_initial_labels_are_automatic(self):
        for index, (label, pinned) in enumerate([("", False), ("9", False), ("09", False), ("９", True), ("Topic", True)]):
            connection = FakeConnection(self.coordinator, [pane(title="Native Topic")], [tab(label)], f"/fake/{index}.sock")
            await self.coordinator.reconcile(connection)
            state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
            self.assertEqual(bool(state.get("pinned")), pinned)

    async def test_pane_updated_refreshes_generated_title(self):
        connection = FakeConnection(self.coordinator, [pane(title="First Topic")])
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        connection.refreshed_panes = [pane(title="Generated Topic")]
        await self.coordinator.handle_herdr_event(connection, {"event": "pane.updated", "data": {}})
        self.assertEqual(connection.renames[-1], ("w1:t1", "Generated Topic"))

    async def test_fake_socket_snapshot_and_rename(self):
        socket_path = Path(self.tmp.name) / "herdr.sock"
        requests = []
        snapshot = {"version": "0.8.0", "protocol": 16, "workspaces": [], "tabs": [tab()], "panes": [pane()], "layouts": [], "agents": []}
        async def serve(reader, writer):
            request = json.loads(await reader.readline())
            requests.append(request)
            result = {"type": "session_snapshot", "snapshot": snapshot} if request["method"] == "session.snapshot" else {"type": "ok"}
            writer.write(json.dumps({"id": request["id"], "result": result}).encode() + b"\n")
            await writer.drain()
            writer.close()
            await writer.wait_closed()
        server = await asyncio.start_unix_server(serve, str(socket_path))
        connection = TITLE.HerdrConnection(self.coordinator, socket_path)
        async with server:
            await connection.refresh_snapshot()
            await connection.rename("w1:t1", "Native Topic")
        self.assertEqual([item["method"] for item in requests], ["session.snapshot", "tab.rename"])

    async def test_first_owner_remains_stable(self):
        panes = [pane("w1:p1", "claude", "Claude Topic"), pane("w1:p2", "codex", "Codex Topic")]
        connection = FakeConnection(self.coordinator, panes, [tab(count=2)])
        await self.coordinator.reconcile(connection)
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        self.assertEqual(state["owner_pane"], "w1:p1")
        panes.reverse()
        await self.coordinator.reconcile(connection)
        self.assertEqual(state["owner_pane"], "w1:p1")

    async def test_restart_grace_then_re_election(self):
        connection = FakeConnection(self.coordinator, [pane("w1:p1", None), pane("w1:p2", "codex", "Codex Topic")], [tab(count=2)])
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        state.update({"owner_pane": "w1:p1", "owner_kind": "claude", "epoch": 1, "title": "1"})
        await self.coordinator.reconcile(connection)
        self.assertEqual(state["owner_pane"], "w1:p1")
        state["owner_ineligible_since"] = time.time() - TITLE.OWNER_RESTART_GRACE - 1
        await self.coordinator.reconcile(connection)
        self.assertEqual(state["owner_pane"], "w1:p2")
        self.assertEqual(connection.renames[-1], ("w1:t1", "Codex Topic"))

    async def test_manual_rename_pins(self):
        connection = FakeConnection(self.coordinator, [pane(title="Native Topic")])
        await self.coordinator.reconcile(connection)
        await self.coordinator.handle_herdr_event(connection, {"event": "tab.renamed", "data": {"tab_id": "w1:t1", "label": "Pinned"}})
        self.assertTrue(self.coordinator.state.tab(connection.socket_path, "w1:t1")["pinned"])

    async def test_offline_manual_rename_is_preserved(self):
        connection = FakeConnection(self.coordinator, [pane(title="Automatic")], [tab("Automatic")])
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        state.update({"owner_pane": "w1:p1", "owner_kind": "codex", "title": "Automatic", "pinned": False})
        connection.snapshot["tabs"][0]["label"] = "Manual Offline"
        await self.coordinator.reconcile(connection)
        self.assertTrue(state["pinned"])

    async def test_expected_rename_is_not_pinned(self):
        connection = FakeConnection(self.coordinator, [pane(title="New")], [tab("New")])
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        state.update({"owner_pane": "w1:p1", "owner_kind": "codex", "title": "Old", "pinned": False})
        connection.expected_renames[("w1:t1", "New")] = 1
        await self.coordinator.handle_herdr_event(connection, {"event": "tab.renamed", "data": {"tab_id": "w1:t1", "label": "New"}})
        await self.coordinator.reconcile(connection)
        self.assertFalse(state.get("pinned", False))

    async def test_new_server_incarnation_clears_old_pin(self):
        connection = FakeConnection(self.coordinator, [pane(title="Fresh")])
        self.coordinator.confirm_incarnation(connection)
        self.coordinator.state.tab(connection.socket_path, "w1:t1").update({"pinned": True, "title": "Old"})
        connection.identity = [1, 200, 2000]
        self.coordinator.confirm_incarnation(connection)
        await self.coordinator.reconcile(connection)
        self.assertEqual(connection.renames[-1], ("w1:t1", "Fresh"))

    async def test_auto_control_unpins_and_refreshes(self):
        connection = FakeConnection(self.coordinator, [pane(title="Native")], [tab("Manual")])
        self.coordinator.connections[connection.socket_path] = connection
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        state.update({"pinned": True, "title": "Manual"})
        event = {"version": 1, "type": "auto", "socket": connection.socket_path, "tab_id": "w1:t1", "pane_id": "w1:p1"}
        await self.coordinator.handle_datagram(json.dumps(event).encode())
        self.assertFalse(state["pinned"])
        self.assertEqual(connection.renames[-1], ("w1:t1", "Native"))


class SourcePolicyTests(unittest.TestCase):
    def test_config_owns_only_thread_title(self):
        source = (ROOT / "home/programs/mutable-configs.nix").read_text()
        self.assertIn('lines, "tui", "terminal_title", \'["thread-title"]\'', source)

    def test_obsolete_title_paths_are_absent(self):
        combined = "\n".join((ROOT / path).read_text() for path in ["scripts/herdr-title.py", "modules/programs/codex.nix", "home/programs/herdr.nix"])
        for obsolete in ["herdr-title-hook", "qwen_title", "HERDR_TITLE_CREDENTIALS", "herdr-title-credentials.json", "dashscope.aliyuncs.com"]:
            self.assertNotIn(obsolete, combined)
        self.assertFalse((ROOT / "scripts/herdr-title-hook.c").exists())


if __name__ == "__main__":
    unittest.main()
