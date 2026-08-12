#!/usr/bin/env python3

from __future__ import annotations

import asyncio
import collections
import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("herdr_title", ROOT / "scripts/herdr-title.py")
assert SPEC and SPEC.loader
TITLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TITLE)
HOOK = ROOT / "scripts/herdr-title-hook.c"


def pane(pane_id="w1:p1", tab_id="w1:t1", agent="codex", title=None, cwd="/tmp/project"):
    return {
        "pane_id": pane_id, "tab_id": tab_id, "workspace_id": "w1", "terminal_id": pane_id,
        "agent": agent, "display_agent": agent, "terminal_title_stripped": title,
        "cwd": cwd, "agent_status": "working", "focused": True, "revision": 1,
    }


def tab(tab_id="w1:t1", label="1", count=1):
    return {"tab_id": tab_id, "workspace_id": "w1", "number": 1, "label": label, "focused": True, "pane_count": count, "agent_status": "working"}


class FakeConnection:
    def __init__(self, coordinator, socket_path, panes, tabs=None):
        self.coordinator = coordinator
        self.socket_path = socket_path
        self.snapshot = {"panes": panes, "tabs": tabs or [tab()]}
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

    async def refresh_snapshot(self):
        await self.coordinator.reconcile(self)


class HerdrTitleTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.coordinator = TITLE.Coordinator(root / "config", root / "runtime", root / "state", root / "credentials")

    async def asyncTearDown(self):
        for task in self.coordinator.generations.values():
            task.cancel()
        self.tmp.cleanup()

    async def test_claude_title_mirrors_exact_sanitized_value(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane(agent="claude", title="  Fix\n\x1bTabs  ")])
        await self.coordinator.reconcile(connection)
        self.assertEqual(connection.renames, [("w1:t1", "Fix Tabs")])

    async def test_claude_title_is_not_limited_to_qwen_length(self):
        title = "A" * 80
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane(agent="claude", title=title)])
        await self.coordinator.reconcile(connection)
        self.assertEqual(connection.renames, [("w1:t1", title)])

    async def test_initial_claude_custom_label_is_pinned(self):
        connection = FakeConnection(
            self.coordinator, "/fake/herdr.sock",
            [pane(agent="claude", title="Claude Automatic Topic")],
            [tab(label="Existing Manual Topic")],
        )
        await self.coordinator.reconcile(connection)
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        self.assertTrue(state["pinned"])
        self.assertEqual(state["title"], "Existing Manual Topic")
        self.assertEqual(connection.renames, [])

    async def test_initial_codex_custom_label_blocks_session_fallback(self):
        connection = FakeConnection(
            self.coordinator, "/fake/herdr.sock", [pane(agent="codex")],
            [tab(label="Existing Manual Topic")],
        )
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        event = {
            "version": 1, "type": "codex_session", "socket": connection.socket_path,
            "pane_id": "w1:p1", "tab_id": "w1:t1", "session_id": "s1", "cwd": "/tmp/project",
        }
        await self.coordinator.handle_datagram(json.dumps(event).encode())
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        self.assertTrue(state["pinned"])
        self.assertEqual(state["title"], "Existing Manual Topic")
        self.assertEqual(connection.renames, [])

    async def test_pinned_codex_prompt_stays_local_until_auto(self):
        connection = FakeConnection(
            self.coordinator, "/fake/herdr.sock", [pane(agent="codex")],
            [tab(label="Existing Manual Topic")],
        )
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        calls = 0

        async def generated(*_args):
            nonlocal calls
            calls += 1
            return "Generated After Auto"

        self.coordinator.qwen_title = generated
        event = {
            "version": 1, "type": "codex_prompt", "socket": connection.socket_path,
            "pane_id": "w1:p1", "tab_id": "w1:t1", "session_id": "s1",
            "cwd": "/tmp/project", "prompt": "Implement a substantial pinned privacy regression",
        }
        await self.coordinator.handle_datagram(json.dumps(event).encode())
        key = self.coordinator.generation_key(connection.socket_path, "w1:t1")
        await asyncio.sleep(0.3)
        self.assertEqual(calls, 0)
        self.assertNotIn(key, self.coordinator.generation_pending)
        self.assertNotIn(key, self.coordinator.generations)
        self.assertEqual(connection.renames, [])

        await self.coordinator.handle_control({
            "type": "auto", "socket": connection.socket_path,
            "pane_id": "w1:p1", "tab_id": "w1:t1",
        })
        await self.coordinator.handle_datagram(json.dumps(event | {
            "prompt": "Implement generation after automatic titles resume",
        }).encode())
        await asyncio.wait_for(self.coordinator.generations[key], 1)
        self.assertEqual(calls, 1)
        self.assertEqual(connection.renames[-1], ("w1:t1", "Generated After Auto"))

    async def test_raw_fake_socket_snapshot_and_rename(self):
        socket_path = Path(self.tmp.name) / "herdr.sock"
        requests = []
        snapshot = {"version": "0.8.0", "protocol": 16, "workspaces": [], "tabs": [tab()], "panes": [pane()], "layouts": [], "agents": []}
        async def serve(reader, writer):
            request = json.loads(await reader.readline())
            requests.append(request)
            if request["method"] == "session.snapshot":
                result = {"type": "session_snapshot", "snapshot": snapshot}
            else:
                result = {"type": "ok"}
            writer.write(json.dumps({"id": request["id"], "result": result}).encode() + b"\n")
            await writer.drain()
            writer.close()
            await writer.wait_closed()
        server = await asyncio.start_unix_server(serve, str(socket_path))
        connection = TITLE.HerdrConnection(self.coordinator, socket_path)
        async with server:
            await connection.refresh_snapshot()
            await connection.rename("w1:t1", "Generated Topic")
        self.assertEqual([item["method"] for item in requests], ["session.snapshot", "tab.rename"])
        self.assertEqual(requests[1]["params"], {"tab_id": "w1:t1", "label": "Generated Topic"})

    async def test_multi_pane_first_owner_is_stable(self):
        panes = [pane("w1:p1", agent="claude", title="Claude Topic"), pane("w1:p2", agent="codex")]
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", panes, [tab(count=2)])
        await self.coordinator.reconcile(connection)
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        self.assertEqual(state["owner_pane"], "w1:p1")
        panes.reverse()
        await self.coordinator.reconcile(connection)
        self.assertEqual(state["owner_pane"], "w1:p1")

    async def test_manual_rename_pins_and_cancels(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane()])
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        pending = asyncio.create_task(asyncio.sleep(30))
        key = self.coordinator.generation_key(connection.socket_path, "w1:t1")
        self.coordinator.generations[key] = pending
        await self.coordinator.handle_herdr_event(connection, {"event": "tab.renamed", "data": {"tab_id": "w1:t1", "label": "Pinned by user"}})
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        self.assertTrue(state["pinned"])
        self.assertNotIn(key, self.coordinator.generation_pending)
        # An already-running HTTP thread cannot be force-cancelled safely; its
        # sequence is invalidated and its eventual result is discarded.
        self.assertGreater(self.coordinator.prompt_seq[key], 0)

    async def test_reconnect_snapshot_preserves_missed_manual_rename(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane(agent="claude", title="Automatic Topic")], [tab(label="Automatic Topic")])
        state = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        state.update({"owner_pane": "w1:p1", "owner_kind": "claude", "title": "Automatic Topic", "pinned": False})
        connection.snapshot["tabs"][0]["label"] = "Manual While Offline"
        await self.coordinator.reconcile(connection)
        self.assertTrue(state["pinned"])
        self.assertEqual(state["title"], "Manual While Offline")
        self.assertEqual(connection.renames, [])

    async def test_server_incarnation_change_clears_reused_tab_identity(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane(agent="claude", title="Fresh Claude Topic")])
        self.coordinator.confirm_incarnation(connection)
        old = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        old.update({"pinned": True, "title": "Old Manual Topic", "session_id": "old-session", "owner_pane": "w1:p1"})
        self.coordinator.state.save()

        # A reconnect to the same live socket preserves manual state.
        self.coordinator.confirm_incarnation(connection)
        self.assertTrue(self.coordinator.state.tab(connection.socket_path, "w1:t1")["pinned"])

        # A recreated socket can reuse opaque IDs, but is a fresh namespace.
        connection.identity = [1, 200, 2000]
        self.coordinator.confirm_incarnation(connection)
        self.assertNotIn(f"{connection.socket_path}\0w1:t1", self.coordinator.state.data["tabs"])
        await self.coordinator.reconcile(connection)
        fresh = self.coordinator.state.tab(connection.socket_path, "w1:t1")
        self.assertFalse(fresh.get("pinned", False))
        self.assertNotIn("session_id", fresh)
        self.assertEqual(connection.renames[-1], ("w1:t1", "Fresh Claude Topic"))

    async def test_server_removal_cancels_pending_generation(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane()])
        key = self.coordinator.generation_key(connection.socket_path, "w1:t1")
        self.coordinator.generation_pending[key] = (connection, "w1:t1", "w1:p1", "s1", 1, 1, "prompt", "/tmp")
        task = asyncio.create_task(asyncio.sleep(30))
        self.coordinator.generations[key] = task
        self.coordinator.cancel_socket_generations(connection.socket_path)
        self.assertNotIn(key, self.coordinator.generation_pending)
        self.assertNotIn(key, self.coordinator.generations)
        self.assertTrue(task.cancelling())

    async def test_session_replacement_invalidates_stale_generation(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane()])
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        common = {"version": 1, "socket": connection.socket_path, "pane_id": "w1:p1", "tab_id": "w1:t1", "cwd": "/tmp/project"}
        await self.coordinator.handle_datagram(json.dumps(common | {"type": "codex_session", "session_id": "old"}).encode())
        async def slow(*_args):
            await asyncio.sleep(0.5)
            return "Stale Generated Title"
        self.coordinator.qwen_title = slow
        await self.coordinator.handle_datagram(json.dumps(common | {"type": "codex_prompt", "session_id": "old", "prompt": "Implement the old complicated feature"}).encode())
        await self.coordinator.handle_datagram(json.dumps(common | {"type": "codex_session", "session_id": "new"}).encode())
        await asyncio.sleep(0.35)
        self.assertNotIn(("w1:t1", "Stale Generated Title"), connection.renames)
        self.assertEqual(self.coordinator.state.tab(connection.socket_path, "w1:t1")["session_id"], "new")

    async def test_dynamic_refresh_serializes_and_uses_newest_prompt(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane()])
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        common = {"version": 1, "type": "codex_prompt", "socket": connection.socket_path, "pane_id": "w1:p1", "tab_id": "w1:t1", "session_id": "s1", "cwd": "/tmp/project"}
        active = maximum = 0
        async def generated(prompt, *_args):
            nonlocal active, maximum
            active += 1
            maximum = max(maximum, active)
            await asyncio.sleep(0.1)
            active -= 1
            return "Newest Prompt Topic" if "newest" in prompt else "Older Prompt Topic"
        self.coordinator.qwen_title = generated
        await self.coordinator.handle_datagram(json.dumps(common | {"prompt": "Investigate the older substantial task"}).encode())
        await asyncio.sleep(0.28)
        await self.coordinator.handle_datagram(json.dumps(common | {"prompt": "Implement the newest substantial task"}).encode())
        await asyncio.sleep(0.5)
        self.assertEqual(maximum, 1)
        self.assertEqual(connection.renames[-1], ("w1:t1", "Newest Prompt Topic"))

    async def test_owner_close_during_generation_consumes_stale_request(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane()])
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        calls = 0
        started = asyncio.Event()
        release = asyncio.Event()

        async def generated(*_args):
            nonlocal calls
            calls += 1
            started.set()
            await release.wait()
            return "Closed Pane Topic"

        self.coordinator.qwen_title = generated
        event = {
            "version": 1, "type": "codex_prompt", "socket": connection.socket_path,
            "pane_id": "w1:p1", "tab_id": "w1:t1", "session_id": "s1",
            "cwd": "/tmp/project", "prompt": "Implement a substantial closing pane regression",
        }
        await self.coordinator.handle_datagram(json.dumps(event).encode())
        await asyncio.wait_for(started.wait(), 1)
        connection.snapshot["panes"] = []
        release.set()
        key = self.coordinator.generation_key(connection.socket_path, "w1:t1")
        await asyncio.wait_for(self.coordinator.generations[key], 1)
        self.assertEqual(calls, 1)
        self.assertNotIn(key, self.coordinator.generation_pending)
        self.assertNotIn(key, self.coordinator.generations)
        self.assertNotIn(("w1:t1", "Closed Pane Topic"), connection.renames)

    async def test_secret_skips_qwen_and_uses_fallback(self):
        connection = FakeConnection(self.coordinator, "/fake/herdr.sock", [pane()])
        self.coordinator.connections[connection.socket_path] = connection
        await self.coordinator.reconcile(connection)
        called = False
        async def forbidden(*_args):
            nonlocal called
            called = True
            return "Should Not Happen"
        self.coordinator.qwen_title = forbidden
        event = {"version": 1, "type": "codex_prompt", "socket": connection.socket_path, "pane_id": "w1:p1", "tab_id": "w1:t1", "session_id": "s1", "cwd": "/tmp/project", "prompt": "Use api_key=abcdefghijklmnopqrstuv for this task"}
        await self.coordinator.handle_datagram(json.dumps(event).encode())
        await asyncio.sleep(0.3)
        self.assertFalse(called)
        self.assertEqual(connection.renames[-1], ("w1:t1", "Codex — project"))

    def test_compound_and_vendor_secrets_are_detected(self):
        samples = [
            "GITHUB_TOKEN=ghp_abcdefghijklmnopqrstuvwxyz123456",
            "client_secret=abcdefghijklmnopqrstuvwxyz123456",
            "Use github_pat_abcdefghijklmnopqrstuvwxyz1234567890",
            "Authorization: Bearer abcdefghijklmnopqrstuvwxyz",
        ]
        for sample in samples:
            with self.subTest(sample=sample):
                self.assertTrue(TITLE.contains_secret(sample))

    async def test_generation_failure_is_cosmetic(self):
        with mock.patch.object(self.coordinator, "qwen_title_sync", side_effect=OSError("offline")):
            title = await self.coordinator.qwen_title("Investigate a substantial offline failure", "Old title", "/tmp/project")
        self.assertEqual(title, "Investigate a substantial offline failure")

    def test_title_output_validation(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self, *_args): return None
            def read(self, *_args): return b''
        self.coordinator.read_key = lambda: "not-a-real-key"
        for invalid in ["One", "too many words in this generated title for the tab now", "Good title\nBad line"]:
            response = {"choices": [{"message": {"content": invalid}}]}
            with mock.patch("urllib.request.urlopen", return_value=mock.MagicMock(__enter__=lambda s: mock.MagicMock(read=lambda: json.dumps(response).encode()), __exit__=lambda *a: None)):
                with self.assertRaises(ValueError):
                    self.coordinator.qwen_title_sync("prompt", "prior")

    def test_fake_http_receives_bounded_nonthinking_request(self):
        recorded = {}
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers["Content-Length"])
                recorded["body"] = json.loads(self.rfile.read(length))
                response = json.dumps({"choices": [{"message": {"content": "Build Semantic Titles"}}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(response)))
                self.end_headers()
                self.wfile.write(response)
            def log_message(self, *_args):
                pass
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.coordinator.read_key = lambda: "not-a-real-key"
        endpoint = f"http://127.0.0.1:{server.server_port}/chat/completions"
        try:
            with mock.patch.dict(os.environ, {"HERDR_TITLE_QWEN_ENDPOINT": endpoint}):
                title = self.coordinator.qwen_title_sync("x" * 2000, "Prior")
        finally:
            server.shutdown()
            server.server_close()
        self.assertEqual(title, "Build Semantic Titles")
        self.assertEqual(recorded["body"]["model"], "qwen3.6-flash")
        self.assertFalse(recorded["body"]["enable_thinking"])
        self.assertEqual(recorded["body"]["max_completion_tokens"], 16)
        self.assertLessEqual(len(recorded["body"]["messages"][1]["content"]), 1100)


class HookTests(unittest.TestCase):
    def setUp(self):
        self._hook_dir = tempfile.TemporaryDirectory()
        self._rendered_hook = str(Path(self._hook_dir.name) / "herdr-title-hook")
        subprocess.run(["cc", "-O2", "-Wall", "-Wextra", "-Werror", str(HOOK), "-o", self._rendered_hook], check=True)

    def tearDown(self):
        self._hook_dir.cleanup()

    def run_hook(self, runtime: Path, payload: dict):
        env = os.environ | {"XDG_RUNTIME_DIR": str(runtime), "HERDR_SOCKET_PATH": "/fake/herdr.sock", "HERDR_PANE_ID": "w1:p1", "HERDR_TAB_ID": "w1:t1"}
        start = time.perf_counter()
        result = subprocess.run([self._rendered_hook], input=json.dumps(payload).encode(), env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=1)
        return result, time.perf_counter() - start

    def test_hook_enqueue_is_fail_open_and_nonblocking(self):
        with tempfile.TemporaryDirectory() as tmp:
            runtime = Path(tmp)
            directory = runtime / "herdr-title"
            directory.mkdir()
            server = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            server.bind(str(directory / "events.sock"))
            payload = {"hook_event_name": "UserPromptSubmit", "session_id": "session-1", "turn_id": "turn-1", "cwd": "/tmp/project", "prompt": "Implement browser style semantic titles"}
            result, elapsed = self.run_hook(runtime, payload)
            event = TITLE.Coordinator.decode_datagram(server.recv(32768))
            server.close()
            self.assertEqual(result.returncode, 0)
            self.assertLess(elapsed, 0.1)
            self.assertEqual(event["session_id"], "session-1")
            self.assertEqual(event["prompt"], payload["prompt"])

    def test_hook_unavailable_coordinator_is_fail_open(self):
        with tempfile.TemporaryDirectory() as tmp:
            result, elapsed = self.run_hook(Path(tmp), {"hook_event_name": "SessionStart", "session_id": "session-2", "cwd": "/tmp/project", "source": "startup"})
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertEqual(result.stderr, b"")
            self.assertLess(elapsed, 0.1)

    def test_subagent_is_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            result, _ = self.run_hook(Path(tmp), {"hook_event_name": "UserPromptSubmit", "session_id": "child", "agent_id": "child-1", "agent_type": "worker", "prompt": "rename parent"})
            self.assertEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
