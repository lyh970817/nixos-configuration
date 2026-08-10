from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "screen_verify.py"

# `stage_position`'s fallbacks are only reachable from a compositor that answers
# badly, which the CLI-level fake cannot express, so the module is imported for
# those cases as well as driven through the CLI for everything else.
sys.path.insert(0, str(SCRIPT.parent))

from screen_verify_lib import stage as stage_module  # noqa: E402
from screen_verify_lib import watch as watch_module  # noqa: E402
from screen_verify_lib.state import ScreenError  # noqa: E402

# A small stateful Hyprland stand-in: it models monitor creation and removal,
# workspace rules, focus, and window spawning, and logs every invocation so
# tests can assert the order in which screen-verify drives the compositor.
HYPRCTL_FAKE = r"""
import json, os, subprocess, sys
from pathlib import Path

arguments = sys.argv[1:]
with open(os.environ["FAKE_COMMAND_LOG"], "a") as handle:
    handle.write(json.dumps(["hyprctl", *arguments]) + "\n")

state_path = Path(os.environ["FAKE_HYPR_STATE"])
state = json.loads(state_path.read_text())


def save():
    state_path.write_text(json.dumps(state))


def focused():
    for monitor in state["monitors"]:
        if monitor.get("focused") and not monitor.get("hidden_polls"):
            return monitor
    return {}


def emit(value):
    print(json.dumps(value))


def rule_geometry(rule):
    # The rectangle a `monitor` keyword asks for, or None for `auto`/nonsense.
    if not rule:
        return None
    resolution, _, _ = rule["resolution"].partition("@")
    width, _, height = resolution.partition("x")
    x, _, y = rule["position"].partition("x")
    if not (width.isdigit() and height.isdigit()):
        return None
    if not (x.lstrip("-").isdigit() and y.lstrip("-").isdigit()):
        # `auto` lands here: Hyprland places the output itself.
        return None
    return {
        "x": int(x),
        "y": int(y),
        "width": int(width),
        "height": int(height),
        "scale": float(rule["scale"]),
    }


def apply_monitor_rule(name):
    # Hyprland keys monitor rules by output name and applies one whenever an
    # output of that name appears -- including an output created after the rule
    # was installed, which is what lets a rule place a stage from birth.
    geometry = rule_geometry(state.get("monitor_rules", {}).get(name))
    if geometry is None:
        return
    for monitor in state["monitors"]:
        if monitor.get("name") == name:
            monitor.update(geometry)


command = arguments[0] if arguments else ""
# A transient hyprctl failure has to be expressible: screen-verify must not
# read one as an answer about the compositor's state.
if command and command in os.environ.get("FAKE_HYPRCTL_FAIL", "").split(","):
    sys.exit(1)
if command == "monitors":
    # Hyprland answers `output create` long before the monitor exists, and the
    # new output adopts its workspace later still. Both latencies are modelled
    # as a countdown of `monitors` polls -- never a wall-clock sleep -- so the
    # waiting loops are actually driven instead of collapsing to single shots.
    visible = []
    counted = False
    for monitor in state["monitors"]:
        entry = dict(monitor)
        hidden = entry.pop("hidden_polls", 0)
        unadopted = entry.pop("workspace_polls", 0)
        if hidden:
            monitor["hidden_polls"] = hidden - 1
            counted = True
            continue
        if unadopted:
            monitor["workspace_polls"] = unadopted - 1
            counted = True
            entry["activeWorkspace"] = {"id": 7, "name": "7"}
        visible.append(entry)
    if counted:
        save()
    emit(visible)
elif command == "activeworkspace":
    monitor = focused()
    workspace = dict(monitor.get("activeWorkspace") or {})
    workspace["monitor"] = monitor.get("name")
    emit(workspace)
elif command == "activewindow":
    emit(state.get("activewindow", {}))
elif command == "clients":
    # A window never maps at the instant its process starts, so the same
    # poll-counted latency applies here.
    hidden = state.get("client_hidden_polls", 0)
    clients = []
    if hidden:
        state["client_hidden_polls"] = hidden - 1
        save()
    else:
        for entry in state.get("clients", []):
            client = dict(entry)
            pid_file = client.pop("pid_file", None)
            if pid_file:
                try:
                    client["pid"] = int(Path(pid_file).read_text().strip())
                except (OSError, ValueError):
                    client["pid"] = 0
            clients.append(client)
    emit(clients)
elif command == "getoption":
    emit({"custom": "4"})
elif command == "keyword":
    if arguments[1:2] == ["workspace"]:
        rule = {}
        for field in arguments[2].split(","):
            key, _, value = field.partition(":")
            rule[key] = value
        if rule.get("name") and rule.get("monitor"):
            state.setdefault("workspace_rules", {})[rule["monitor"]] = rule["name"]
            save()
    elif arguments[1:2] == ["monitor"]:
        fields = arguments[2].split(",")
        if len(fields) == 4:
            state.setdefault("monitor_rules", {})[fields[0]] = {
                "resolution": fields[1],
                "position": fields[2],
                "scale": fields[3],
            }
            # A rule for an output that already exists takes effect at once; one
            # for an output that does not is remembered until it appears.
            apply_monitor_rule(fields[0])
            save()
    print("ok")
elif command == "output":
    if arguments[1:2] == ["create"]:
        snapshot = os.environ.get("FAKE_SESSION_SNAPSHOT")
        source = os.environ.get("FAKE_SESSION_FILE")
        if snapshot and source:
            try:
                Path(snapshot).write_text(Path(source).read_text())
            except OSError:
                pass
        name = arguments[3]
        rule = state.get("workspace_rules", {}).get(name)
        if rule and not state.get("ignore_workspace_rules"):
            workspace = {"id": -13, "name": rule}
        else:
            workspace = {"id": 7, "name": "7"}
        for monitor in state["monitors"]:
            monitor["focused"] = False
        # Hyprland places a new output automatically, scanning rightward from
        # the origin, so it lands flush against the right edge of the layout --
        # which is exactly the placement screen-verify has to move it off.
        # `output create` takes no position, so this is where an output with no
        # rule of its own is born, and it stays there until a rule arrives.
        edge = 0
        for monitor in state["monitors"]:
            if isinstance(monitor.get("x"), int) and isinstance(
                monitor.get("width"), int
            ):
                edge = max(edge, monitor["x"] + monitor["width"])
        created = {
            "name": name,
            "focused": True,
            "x": edge,
            "y": 0,
            "width": 1920,
            "height": 1080,
            "scale": 1.0,
            "activeWorkspace": workspace,
        }
        # A rule installed before creation is applied by name as the output
        # appears, so an output created under one is never auto-placed at all.
        created.update(rule_geometry(state.get("monitor_rules", {}).get(name)) or {})
        # The rectangle the output was born with, kept so tests can ask where it
        # sat during the interval before any later rule could move it.
        state.setdefault("created_at", {})[name] = {
            key: created[key] for key in ("x", "y", "width", "height")
        }
        if state.get("create_hidden_polls"):
            created["hidden_polls"] = state["create_hidden_polls"]
        if state.get("create_workspace_polls"):
            created["workspace_polls"] = state["create_workspace_polls"]
        state["monitors"].append(created)
    elif arguments[1:2] == ["remove"] and not state.get("ignore_output_removals"):
        name = arguments[2]
        state["monitors"] = [
            monitor for monitor in state["monitors"] if monitor.get("name") != name
        ]
        if state["monitors"] and not any(m.get("focused") for m in state["monitors"]):
            state["monitors"][0]["focused"] = True
    save()
    print("ok")
elif command == "dispatch":
    action = arguments[1] if len(arguments) > 1 else ""
    if action == "exec":
        specification = arguments[2]
        if specification.startswith("["):
            specification = specification[specification.index("]") + 1 :].lstrip()
        # Hyprland 0.53.1 calls neither setsid nor setpgid for exec'd
        # children, so a staged process is never a process-group leader.
        subprocess.Popen(
            ["/bin/sh", "-c", specification],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    elif action == "focusmonitor":
        for monitor in state["monitors"]:
            monitor["focused"] = monitor.get("name") == arguments[2]
        save()
    elif action == "focuswindow":
        state["focused_window"] = arguments[2]
        save()
    elif action == "moveworkspacetomonitor" and not state.get("ignore_workspace_moves"):
        target, _, destination = arguments[2].partition(" ")
        name = target.split(":", 1)[-1]
        for monitor in state["monitors"]:
            if monitor.get("name") == destination:
                monitor["activeWorkspace"] = {"id": -13, "name": name}
        save()
    print("ok")
else:
    print("ok")
"""


class ScreenVerifyCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.runtime = self.root / "runtime"
        self.state = self.root / "state"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.hypr_state = self.root / "hypr-state.json"
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "HOME": str(self.root / "home"),
                "XDG_RUNTIME_DIR": str(self.runtime),
                "XDG_STATE_HOME": str(self.state),
                "PATH": f"{self.bin}:{os.environ['PATH']}",
                "FAKE_COMMAND_LOG": str(self.log),
                "FAKE_HYPR_STATE": str(self.hypr_state),
            }
        )
        # The stage watcher derives its socket from this; a signature leaking
        # in from a real Hyprland session would leave every test's watcher
        # reading real compositor events instead of exiting at once. Tests
        # that want a watcher install their own socket via `enable_socket2`.
        self.environment.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        self.socket2 = None
        self.connections: list[socket.socket] = []
        self.write_hypr_state()
        self.fake(
            "hyprctl",
            f"""#!/bin/sh
{sys.executable} - "$@" <<'PY'
{HYPRCTL_FAKE}
PY
""",
        )
        self.fake(
            "grim",
            f"""#!/bin/sh
{sys.executable} - "$@" <<'PY'
import json, os, pathlib, sys
with open(os.environ['FAKE_COMMAND_LOG'], 'a') as handle: handle.write(json.dumps(['grim', *sys.argv[1:]]) + '\\n')
pathlib.Path(sys.argv[-1]).write_bytes(b'PNG')
PY
""",
        )
        self.fake(
            "notify-send",
            f"""#!/bin/sh
{sys.executable} - "$@" <<'PY'
import json, os, sys
with open(os.environ['FAKE_COMMAND_LOG'], 'a') as handle: handle.write(json.dumps(['notify-send', *sys.argv[1:]]) + '\\n')
PY
""",
        )
        self.fake("gsettings", "#!/bin/sh\nprintf \"'prefer-dark'\\n\"\n")
        self.fake("darkman", "#!/bin/sh\nprintf 'dark\\n'\n")

    def tearDown(self) -> None:
        for connection in self.connections:
            connection.close()
        if self.socket2 is not None:
            self.socket2.close()
        self.temporary.cleanup()

    def enable_socket2(self) -> None:
        """A listening socket2 stand-in at the path the watcher derives."""
        signature = "fakesig"
        hypr_dir = self.runtime / "hypr" / signature
        hypr_dir.mkdir(parents=True, exist_ok=True)
        self.socket2 = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket2.bind(str(hypr_dir / ".socket2.sock"))
        self.socket2.listen(4)
        self.socket2.settimeout(10.0)
        self.environment["HYPRLAND_INSTANCE_SIGNATURE"] = signature

    def accept_watcher(self) -> socket.socket:
        connection, _ = self.socket2.accept()
        self.connections.append(connection)
        return connection

    def watcher_record(self, session: str) -> dict:
        data = json.loads(self.session_file(session).read_text())
        return data["stage"]["watcher"]

    def fake(self, name: str, contents: str) -> Path:
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)
        return path

    def write_hypr_state(self, **overrides) -> None:
        state = {
            "monitors": [
                {
                    "name": "DP-1",
                    "focused": True,
                    # Real Hyprland always reports a position; without one the
                    # placement tests would only ever exercise the fallback.
                    "x": 0,
                    "y": 0,
                    "width": 2560,
                    "height": 1440,
                    "scale": 1.25,
                    "activeWorkspace": {"id": 1, "name": "1"},
                }
            ],
            "activewindow": {
                "address": "0xuser",
                "at": [10, 20],
                "size": [800, 600],
            },
            "clients": [],
            "workspace_rules": {},
        }
        state.update(overrides)
        self.hypr_state.write_text(json.dumps(state))

    def set_clients(self, clients: list[dict]) -> None:
        state = json.loads(self.hypr_state.read_text())
        state["clients"] = clients
        self.hypr_state.write_text(json.dumps(state))

    def patch_hypr_state(self, **updates) -> None:
        state = json.loads(self.hypr_state.read_text())
        state.update(updates)
        self.hypr_state.write_text(json.dumps(state))

    def set_active_workspace(self, monitor: str, workspace: dict) -> None:
        state = json.loads(self.hypr_state.read_text())
        for entry in state["monitors"]:
            if entry["name"] == monitor:
                entry["activeWorkspace"] = workspace
        self.hypr_state.write_text(json.dumps(state))

    def quiet_gsettings(self) -> None:
        """`set` prints nothing: preview does not capture it, so it would
        otherwise land in front of the command's own JSON on stdout."""
        self.fake(
            "gsettings",
            "#!/bin/sh\nif [ \"$1\" = get ]; then printf \"'prefer-dark'\\n\"; fi\n",
        )

    def failing_gsettings(self) -> None:
        """`gsettings get` still answers, but every `set` fails."""
        self.fake(
            "gsettings",
            "#!/bin/sh\nif [ \"$1\" = get ]; then printf \"'prefer-dark'\\n\"; "
            "else exit 1; fi\n",
        )

    def session_file(self, session: str) -> Path:
        return self.runtime / "screen-verify" / session / "session.json"

    def tamper(self, session: str, **stage) -> None:
        path = self.session_file(session)
        data = json.loads(path.read_text())
        data["stage"] = stage
        path.write_text(json.dumps(data))

    def run_cli(self, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
        )

    def drop_fake_monitor(self, name: str) -> None:
        state = json.loads(self.hypr_state.read_text())
        state["monitors"] = [
            monitor for monitor in state["monitors"] if monitor["name"] != name
        ]
        if state["monitors"] and not any(m.get("focused") for m in state["monitors"]):
            state["monitors"][0]["focused"] = True
        self.hypr_state.write_text(json.dumps(state))

    def hypr_monitors(self) -> list[str]:
        state = json.loads(self.hypr_state.read_text())
        return [monitor["name"] for monitor in state["monitors"]]

    def hyprctl_calls(self) -> list[list[str]]:
        return [command for command in self.commands() if command[0] == "hyprctl"]

    def call_index(self, prefix: list[str]) -> int:
        calls = self.hyprctl_calls()
        for index, command in enumerate(calls):
            if command[: len(prefix)] == prefix:
                return index
        raise AssertionError(f"hyprctl call not found: {prefix}")

    def stage_names(self, session: str) -> tuple[str, str]:
        return f"svstage{session[:8]}", f"svws{session[:8]}"

    def stage_keyword(self) -> str:
        """The `monitor` keyword argument that sized and placed the stage."""
        command = next(
            command
            for command in self.hyprctl_calls()
            if command[:3] == ["hyprctl", "keyword", "monitor"]
        )
        return command[3]

    def stage_rectangle(self, session: str) -> tuple[int, int, int, int]:
        """(x, y, width, height) the stage was asked to occupy."""
        output, _ = self.stage_names(session)
        name, resolution, position, _ = self.stage_keyword().split(",")
        self.assertEqual(name, output)
        self.assertNotEqual(
            position,
            "auto",
            "the stage was placed automatically, flush against the user's screen",
        )
        size = re.fullmatch(r"(\d+)x(\d+)@\d+", resolution)
        corner = re.fullmatch(r"(-?\d+)x(-?\d+)", position)
        self.assertIsNotNone(size, resolution)
        self.assertIsNotNone(corner, position)
        return int(corner[1]), int(corner[2]), int(size[1]), int(size[2])

    def real_monitor_rectangles(self, session: str) -> list[tuple[int, int, int, int]]:
        """(x, y, width, height) of every monitor that is not the stage."""
        output, _ = self.stage_names(session)
        state = json.loads(self.hypr_state.read_text())
        return [
            (monitor["x"], monitor["y"], monitor["width"], monitor["height"])
            for monitor in state["monitors"]
            if monitor["name"] != output
        ]

    def eventually(self, predicate, message: str, timeout: float = 10.0):
        deadline = time.monotonic() + timeout
        while True:
            value = predicate()
            if value:
                return value
            if time.monotonic() >= deadline:
                raise AssertionError(message)
            time.sleep(0.05)

    def reaped(self, pid: int) -> bool:
        try:
            stat = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
        except OSError:
            return True
        return stat.rsplit(")", 1)[1].split()[0] == "Z"

    def recorded_argv(self, argv_file: Path) -> list[str]:
        """The arguments a `sleeper` helper received, in order.

        The record is NUL-separated rather than newline-separated: a
        newline-separated one cannot express an argument that contains a
        newline, so such an argument would be silently unrepresentable and any
        round-trip assertion about it would pass no matter what was delivered.
        """
        recorded = argv_file.read_text(encoding="utf-8").split("\0")
        if recorded and recorded[-1] == "":
            # Every argument is terminated, so the split leaves a final empty
            # element that is a separator artefact, not an empty argument.
            recorded.pop()
        return recorded

    def sleeper(self, name: str, pid_file: Path, argv_file: Path | None = None) -> Path:
        """A long-lived helper that owns a child, so descendants are testable."""
        record = (
            f"for argument in \"$@\"; do printf '%s\\0' \"$argument\" >> {argv_file}; done\n"
            if argv_file
            else ""
        )
        return self.fake(
            name,
            f"""#!/bin/sh
{record}sleep 30 &
printf '%s' $! > {self.child_pid_file(pid_file)}
printf '%s' $$ > {pid_file}
wait
""",
        )

    def child_pid_file(self, pid_file: Path) -> Path:
        return pid_file.with_name(pid_file.name + ".child")

    def cli(self, *arguments: str, check: bool = True) -> dict:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *arguments],
            env=self.environment,
            capture_output=True,
            text=True,
            check=check,
        )
        return json.loads(result.stdout) if result.stdout else {}

    def commands(self) -> list[list[str]]:
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def begin(self) -> str:
        result = self.cli("begin")
        self.assertEqual(result["mode"], "dark")
        self.assertRegex(result["session"], r"^[0-9a-f]{24}$")
        return result["session"]

    def test_focused_capture_is_private_notified_and_audited(self) -> None:
        session = self.begin()
        self.assertFalse(any(command[0] == "notify-send" for command in self.commands()))
        result = self.cli("capture", "--session", session)

        capture = Path(result["path"])
        self.assertEqual(capture.read_bytes(), b"PNG")
        self.assertEqual(capture.stat().st_mode & 0o777, 0o600)
        self.assertIn(["grim", "-o", "DP-1", str(capture)], self.commands())
        self.assertTrue(any(command[0] == "notify-send" for command in self.commands()))
        capture_commands = [
            command[0]
            for command in self.commands()
            if command[0] in {"grim", "notify-send"}
        ]
        self.assertEqual(capture_commands, ["grim", "notify-send"])

        audit = (self.state / "screen-verify/audit.jsonl").read_text()
        self.assertIn('"event":"capture"', audit)
        self.assertNotIn(str(capture), audit)
        self.assertIn('"monitor":"DP-1"', audit)

    def test_window_region_monitor_and_all_targets_map_to_grim(self) -> None:
        session = self.begin()
        cases = [
            (["--target", "window"], ["-g", "10,20 800x600"]),
            (["--target", "region", "--geometry", "1,2 30x40"], ["-g", "1,2 30x40"]),
            (["--target", "monitor", "--monitor", "HDMI-A-1"], ["-o", "HDMI-A-1"]),
            (["--target", "all"], []),
        ]
        for arguments, expected in cases:
            result = self.cli("capture", "--session", session, *arguments)
            command = next(
                command
                for command in reversed(self.commands())
                if command[0] == "grim"
            )
            self.assertEqual(command[1:-1], expected)
            self.assertEqual(Path(command[-1]), Path(result["path"]))

    def test_end_removes_captures_and_terminates_owned_process(self) -> None:
        session = self.begin()
        capture = Path(self.cli("capture", "--session", session)["path"])
        launch = self.cli(
            "launch",
            "--session",
            session,
            "--no-stage",
            "--wait-seconds",
            "0",
            "--",
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
        )
        self.assertEqual(launch["spawn"], "direct")
        self.assertIsNone(launch["stage"])
        self.assertEqual(
            [command for command in self.hyprctl_calls() if command[1] == "output"], []
        )
        self.assertEqual(
            [command for command in self.hyprctl_calls() if command[1] == "dispatch"],
            [],
        )

        result = self.cli("end", "--session", session)

        self.assertTrue(result["cleaned"])
        self.assertFalse(result["stage_removed"])
        self.assertEqual(result["terminated"], 1)
        self.assertFalse(capture.parent.exists())
        with self.assertRaises(ProcessLookupError):
            os.kill(launch["pid"], 0)

    def test_keep_open_process_survives_cleanup(self) -> None:
        session = self.begin()
        launch = self.cli(
            "launch",
            "--keep-open",
            "--session",
            session,
            "--no-stage",
            "--wait-seconds",
            "0",
            "--",
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
        )
        try:
            result = self.cli("end", "--session", session)
            self.assertEqual(result["terminated"], 0)
            os.kill(launch["pid"], 0)
        finally:
            os.killpg(launch["pid"], 15)

    def test_abandoned_sessions_are_purged_on_begin(self) -> None:
        old_session = self.begin()
        old_path = self.runtime / "screen-verify" / old_session
        old_time = time.time() - 25 * 60 * 60
        os.utime(old_path, (old_time, old_time))

        self.begin()

        self.assertFalse(old_path.exists())
        audit = (self.state / "screen-verify/audit.jsonl").read_text()
        self.assertIn('"event":"purge"', audit)

    def test_audit_rotation_drops_entries_older_than_90_days(self) -> None:
        audit_dir = self.state / "screen-verify"
        audit_dir.mkdir(parents=True)
        audit_path = audit_dir / "audit.jsonl"
        audit_path.write_text(
            '{"time":"2020-01-01T00:00:00+00:00","session":"old","event":"begin","outcome":"ok"}\n'
        )

        self.begin()

        self.assertNotIn('"session":"old"', audit_path.read_text())

    def test_audit_is_strictly_capped_after_each_event(self) -> None:
        audit_dir = self.state / "screen-verify"
        audit_dir.mkdir(parents=True)
        audit_path = audit_dir / "audit.jsonl"
        audit_path.write_text(
            json.dumps(
                {
                    "time": "2099-01-01T00:00:00+00:00",
                    "session": "large",
                    "event": "begin",
                    "outcome": "ok",
                    "padding": "x" * (1024 * 1024),
                }
            )
            + "\n"
        )

        self.begin()

        self.assertLessEqual(audit_path.stat().st_size, 1024 * 1024)

    def test_launch_associates_a_window_without_auditing_identity(self) -> None:
        session = self.begin()
        pid_file = self.root / "client-pid"
        helper = self.bin / "window-app"
        helper.write_text(f"#!/bin/sh\nprintf '%s' $$ > {pid_file}\nsleep 30\n")
        helper.chmod(0o755)
        self.fake(
            "hyprctl",
            f"""#!/bin/sh
if [ "$1" = clients ]; then pid=$(cat {pid_file} 2>/dev/null || printf 0); printf '[{{"address":"0xabc","pid":%s,"class":"Secret App","title":"Secret Document"}}]\\n' "$pid"; else printf '%s\\n' '{{"monitor":"DP-1"}}'; fi
""",
        )

        result = self.cli(
            "launch",
            "--session",
            session,
            "--no-stage",
            "--wait-seconds",
            "1",
            "--",
            str(helper),
        )
        try:
            self.assertEqual(result["window"]["address"], "0xabc")
            audit = (self.state / "screen-verify/audit.jsonl").read_text()
            self.assertNotIn("Secret App", audit)
            self.assertNotIn("Secret Document", audit)
            self.assertNotIn(str(helper), audit)
        finally:
            self.cli("end", "--session", session)

    def test_starting_mode_is_locked_and_displaced_mode_is_restored(self) -> None:
        mode_file = self.root / "mode"
        mode_file.write_text("dark")
        self.fake(
            "gsettings",
            f"#!/bin/sh\nprintf \"'prefer-%s'\\n\" \"$(cat {mode_file})\"\n",
        )
        self.fake("darkman", "#!/bin/sh\nexit 1\n")
        self.fake("switch-dark", f"#!/bin/sh\nprintf dark > {mode_file}\n")
        self.fake("switch-light", f"#!/bin/sh\nprintf light > {mode_file}\n")
        session = self.begin()
        mode_file.write_text("light")

        ensured = self.cli("ensure-mode", "--session", session)
        self.assertEqual(ensured["mode"], "dark")
        self.assertEqual(mode_file.read_text(), "dark")

        ended = self.cli("end", "--session", session)
        self.assertEqual(ended["restored_mode"], "light")
        self.assertEqual(mode_file.read_text(), "light")

    def test_reversible_preview_adapters_restore_state_on_end(self) -> None:
        actions = self.root / "actions"
        target = self.root / "home/.config/foot/foot.ini"
        original = self.root / "original.ini"
        preview = self.root / "preview.ini"
        target.parent.mkdir(parents=True)
        original.write_text("original")
        preview.write_text("preview")
        target.symlink_to(original)
        self.fake(
            "gsettings",
            f"""#!/bin/sh
if [ "$1" = get ]; then printf "'prefer-dark'\\n"; else printf 'gsettings %s\\n' "$*" >> {actions}; fi
""",
        )
        self.fake(
            "hyprctl",
            f"""#!/bin/sh
if [ "$1" = getoption ]; then printf '%s\\n' '{{"custom":"4"}}'; elif [ "$1" = eval ]; then printf 'hyprctl %s\\n' "$*" >> {actions}; else printf '%s\\n' '{{"monitor":"DP-1"}}'; fi
""",
        )
        self.fake(
            "makoctl",
            f"""#!/bin/sh
if [ "$1" = mode ] && [ "$#" = 1 ]; then printf 'default\\n'; else printf 'makoctl %s\\n' "$*" >> {actions}; fi
""",
        )
        session = self.begin()

        self.cli(
            "preview",
            "symlink",
            "--session",
            session,
            "--target",
            str(target),
            "--source",
            str(preview),
        )
        self.cli(
            "preview",
            "gsettings",
            "--session",
            session,
            "--schema",
            "org.example",
            "--key",
            "theme",
            "--value",
            "'preview'",
        )
        self.cli(
            "preview",
            "hypr-keyword",
            "--session",
            session,
            "--keyword",
            "general:gaps_in",
            "--value",
            "20",
        )
        self.cli(
            "preview",
            "mako-mode",
            "--session",
            session,
            "--mode",
            "dark",
        )
        self.assertEqual(target.resolve(), preview)

        result = self.cli("end", "--session", session)

        self.assertEqual(result["restored_previews"], 4)
        self.assertEqual(target.resolve(), original)
        action_lines = actions.read_text().splitlines()
        self.assertIn("gsettings set org.example theme 'preview'", action_lines)
        self.assertIn("gsettings set org.example theme 'prefer-dark'", action_lines)
        self.assertIn(
            "hyprctl eval hl.config({ general = { gaps_in = 20 } })", action_lines
        )
        self.assertIn(
            "hyprctl eval hl.config({ general = { gaps_in = 4 } })", action_lines
        )
        self.assertIn("makoctl mode -s dark", action_lines)
        self.assertIn("makoctl mode -s default", action_lines)

    def test_symlink_preview_rejects_a_parent_that_resolves_outside_home(self) -> None:
        outside = self.root / "outside"
        outside.mkdir()
        escape = self.root / "home/escape"
        escape.parent.mkdir(parents=True)
        escape.symlink_to(outside, target_is_directory=True)
        source = self.root / "source"
        source.write_text("preview")
        session = self.begin()

        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "preview",
                "symlink",
                "--session",
                session,
                "--target",
                str(escape / "theme"),
                "--source",
                str(source),
            ],
            env=self.environment,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inside the home directory", result.stderr)
        self.assertFalse((outside / "theme").exists())
        self.cli("end", "--session", session)

    def test_stage_installs_both_rules_before_creating_the_output(self) -> None:
        # Hyprland applies a rule by output name as the output appears, and
        # both rules depend on that. Without the workspace rule first the
        # output adopts a numeric workspace and every capture comes back blank;
        # without the monitor rule first the output is auto-placed flush
        # against the user's screen and stays there, reachable by the pointer,
        # until the rule lands -- `output create` takes no position of its own.
        session = self.begin()
        output, workspace = self.stage_names(session)

        result = self.cli("stage", "--session", session)

        self.assertEqual(result["output"], output)
        self.assertEqual(result["workspace"], workspace)
        workspace_rule = self.call_index(
            [
                "hyprctl",
                "keyword",
                "workspace",
                f"name:{workspace},monitor:{output},default:true",
            ]
        )
        monitor_rule = self.call_index(["hyprctl", "keyword", "monitor"])
        creation = self.call_index(["hyprctl", "output", "create", "headless", output])
        self.assertLess(workspace_rule, creation)
        self.assertLess(
            monitor_rule,
            creation,
            "the stage was created before it had a position to be created at",
        )
        self.assertIn(output, self.hypr_monitors())

    def test_the_stage_is_off_screen_from_the_moment_it_is_created(self) -> None:
        # The ordering above exists for this, and only this: the rectangle the
        # output is born with -- not the one it is moved to afterwards -- has
        # to already clear every real monitor. A stage repositioned after
        # creation passes every other placement test here while still leaving a
        # window in which the pointer can walk onto it.
        session = self.begin()
        output, _ = self.stage_names(session)

        self.cli("stage", "--session", session)

        state = json.loads(self.hypr_state.read_text())
        birth = state["created_at"][output]
        for monitor_x, monitor_y, _, _ in self.real_monitor_rectangles(session):
            self.assertLessEqual(
                birth["x"] + birth["width"] + stage_module.STAGE_GAP, monitor_x
            )
            self.assertLessEqual(
                birth["y"] + birth["height"] + stage_module.STAGE_GAP, monitor_y
            )

    def test_the_size_and_the_position_come_from_one_layout_query(self) -> None:
        # The rule carries a size and a position, and both are read out of the
        # same `monitors` answer. Two queries can disagree: the second one
        # failing on a layout whose true origin is negative would put the
        # position on its 0,0 fallback while the size still describes a real
        # monitor, and the stage would land on top of one.
        session = self.begin()

        self.cli("stage", "--session", session)

        calls = self.hyprctl_calls()
        window = self.call_index(["hyprctl", "activewindow"])
        # The focus snapshot reads the layout too, and that read is its own;
        # the decision under test is everything between it and the first rule.
        focus_query = next(
            index
            for index, command in enumerate(calls)
            if command[:2] == ["hyprctl", "monitors"] and index > window
        )
        first_rule = self.call_index(["hyprctl", "keyword"])
        self.assertLess(focus_query, first_rule)
        queries = [
            index
            for index, command in enumerate(calls)
            if command[:2] == ["hyprctl", "monitors"]
            and focus_query < index < first_rule
        ]
        self.assertEqual(
            len(queries),
            1,
            "the reference geometry and the placement did not share one snapshot",
        )

    def test_stage_sizes_the_output_from_the_reference_monitor(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)

        self.cli("stage", "--session", session)

        name, resolution, _, scale = self.stage_keyword().split(",")
        self.assertEqual([name, resolution, scale], [output, "2560x1440@60", "1.25"])

    def test_stage_is_placed_up_and_left_of_the_users_monitor(self) -> None:
        session = self.begin()

        self.cli("stage", "--session", session)

        x, y, width, height = self.stage_rectangle(session)
        rectangles = self.real_monitor_rectangles(session)
        self.assertEqual(len(rectangles), 1)
        # "auto" would put the stage flush against the right edge of the user's
        # screen, where the pointer walks straight onto it. The gap is what
        # makes it unreachable, so the clearance is what gets asserted -- never
        # a hardcoded corner, which would stop meaning anything the moment the
        # reference monitor changes size.
        for monitor_x, monitor_y, _, _ in rectangles:
            self.assertLessEqual(x + width + stage_module.STAGE_GAP, monitor_x)
            self.assertLessEqual(y + height + stage_module.STAGE_GAP, monitor_y)

    def test_stage_is_placed_up_and_left_of_every_monitor(self) -> None:
        # Clearing the focused monitor is not enough: the position has to come
        # from the minimum x and the minimum y of the whole layout. Both are
        # negative and they come from different monitors, so the exact corner
        # asserted below pins each axis on its own: a placement blind to either
        # minimum would land somewhere this cannot accept. It also has to be
        # negative on both axes for the geometric check to mean anything --
        # clearance on one axis alone already separates two rectangles, so the
        # overlap test that follows can never catch a single-axis mistake.
        self.write_hypr_state(
            monitors=[
                {
                    "name": "DP-1",
                    "focused": True,
                    "x": 0,
                    "y": 0,
                    "width": 2560,
                    "height": 1440,
                    "scale": 1.25,
                    "activeWorkspace": {"id": 1, "name": "1"},
                },
                {
                    "name": "HDMI-A-1",
                    "focused": False,
                    "x": -1920,
                    "y": 400,
                    "width": 1920,
                    "height": 1080,
                    "scale": 1.0,
                    "activeWorkspace": {"id": 2, "name": "2"},
                },
                {
                    "name": "DP-2",
                    "focused": False,
                    "x": 2560,
                    "y": -300,
                    "width": 1920,
                    "height": 1080,
                    "scale": 1.0,
                    "activeWorkspace": {"id": 3, "name": "3"},
                },
            ]
        )
        session = self.begin()

        self.cli("stage", "--session", session)

        x, y, width, height = self.stage_rectangle(session)
        rectangles = self.real_monitor_rectangles(session)
        self.assertEqual(len(rectangles), 3)
        origin_x = min(rectangle[0] for rectangle in rectangles)
        origin_y = min(rectangle[1] for rectangle in rectangles)
        # Guards the layout above against being edited back into one where
        # either minimum happens to be the zero the fallback would also give.
        self.assertLess(origin_x, 0)
        self.assertLess(origin_y, 0)
        self.assertEqual(
            (x, y),
            (
                origin_x - width - stage_module.STAGE_GAP,
                origin_y - height - stage_module.STAGE_GAP,
            ),
        )
        for monitor_x, monitor_y, _, _ in rectangles:
            self.assertLessEqual(x + width + stage_module.STAGE_GAP, monitor_x)
            self.assertLessEqual(y + height + stage_module.STAGE_GAP, monitor_y)

    def test_the_stage_rectangle_touches_no_real_monitor(self) -> None:
        # Overlap and adjacency are the properties the whole placement exists
        # to avoid, so they are checked as geometry rather than inferred from
        # the corner. HDMI-A-1 is up and left of the focused monitor, so a
        # stage that cleared only the focused one would sit on top of it.
        self.write_hypr_state(
            monitors=[
                {
                    "name": "DP-1",
                    "focused": True,
                    "x": 0,
                    "y": 0,
                    "width": 2560,
                    "height": 1440,
                    "scale": 1.25,
                    "activeWorkspace": {"id": 1, "name": "1"},
                },
                {
                    "name": "HDMI-A-1",
                    "focused": False,
                    "x": -1920,
                    "y": -1080,
                    "width": 1920,
                    "height": 1080,
                    "scale": 1.0,
                    "activeWorkspace": {"id": 2, "name": "2"},
                },
            ]
        )
        session = self.begin()

        self.cli("stage", "--session", session)

        x, y, width, height = self.stage_rectangle(session)
        rectangles = self.real_monitor_rectangles(session)
        self.assertEqual(len(rectangles), 2)
        for monitor_x, monitor_y, monitor_width, monitor_height in rectangles:
            # Strict, so a shared edge counts as a failure: the pointer moves
            # through one continuous coordinate space, and an output the user's
            # screen merely touches is one the cursor can walk onto.
            separated = (
                x + width < monitor_x
                or monitor_x + monitor_width < x
                or y + height < monitor_y
                or monitor_y + monitor_height < y
            )
            self.assertTrue(
                separated,
                f"stage {(x, y, width, height)} touches monitor "
                f"{(monitor_x, monitor_y, monitor_width, monitor_height)}",
            )

    def test_stage_restores_the_focus_it_steals(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)

        self.cli("stage", "--session", session)

        creation = self.call_index(["hyprctl", "output", "create", "headless", output])
        focus_monitor = self.call_index(
            ["hyprctl", "dispatch", "focusmonitor", "DP-1"]
        )
        focus_window = self.call_index(
            ["hyprctl", "dispatch", "focuswindow", "address:0xuser"]
        )
        self.assertLess(creation, focus_monitor)
        self.assertLess(focus_monitor, focus_window)
        state = json.loads(self.hypr_state.read_text())
        focused = [
            monitor["name"] for monitor in state["monitors"] if monitor["focused"]
        ]
        self.assertEqual(focused, ["DP-1"])

    def test_stage_restores_focus_when_no_monitor_reports_it(self) -> None:
        session = self.begin()
        # One monitors query that reports nothing focused must not leave the
        # snapshot empty; the user would be left typing at the hidden stage.
        state = json.loads(self.hypr_state.read_text())
        state["monitors"][0]["focused"] = False
        self.hypr_state.write_text(json.dumps(state))

        self.cli("stage", "--session", session)

        self.assertIn(["hyprctl", "dispatch", "focusmonitor", "DP-1"], self.commands())
        state = json.loads(self.hypr_state.read_text())
        focused = [
            monitor["name"] for monitor in state["monitors"] if monitor["focused"]
        ]
        self.assertEqual(focused, ["DP-1"])

    def test_the_stage_is_recorded_before_the_output_can_exist(self) -> None:
        session = self.begin()
        output, workspace = self.stage_names(session)
        snapshot = self.root / "session-at-create.json"
        self.environment["FAKE_SESSION_FILE"] = str(self.session_file(session))
        self.environment["FAKE_SESSION_SNAPSHOT"] = str(snapshot)

        self.cli("stage", "--session", session)

        at_creation = json.loads(snapshot.read_text())
        self.assertIn("stage", at_creation, "the output was created unrecorded")
        self.assertEqual(at_creation["stage"]["output"], output)
        self.assertEqual(at_creation["stage"]["workspace"], workspace)

    def test_stage_creation_is_idempotent(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)

        first = self.cli("stage", "--session", session)
        second = self.cli("stage", "--session", session)

        self.assertEqual(first, second)
        creations = [
            command
            for command in self.hyprctl_calls()
            if command[:3] == ["hyprctl", "output", "create"]
        ]
        self.assertEqual(len(creations), 1)
        self.assertEqual(self.hypr_monitors().count(output), 1)

    def test_stage_creation_fails_when_the_workspace_is_not_adopted(self) -> None:
        self.write_hypr_state(ignore_workspace_rules=True)
        session = self.begin()
        output, _ = self.stage_names(session)

        result = subprocess.run(
            [sys.executable, str(SCRIPT), "stage", "--session", session],
            env=self.environment,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("workspace", result.stderr)
        self.assertNotIn(output, self.hypr_monitors())
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())
        self.assertFalse(self.cli("status", "--session", session)["stage"])
        self.assertNotIn("stage", json.loads(self.session_file(session).read_text()))

    def test_stage_waits_for_an_output_that_appears_a_poll_later(self) -> None:
        # `output create` returns before the monitor exists, so the first
        # `monitors` query legitimately does not see it yet.
        self.write_hypr_state(create_hidden_polls=2)
        session = self.begin()
        output, workspace = self.stage_names(session)

        result = self.cli("stage", "--session", session)

        self.assertEqual(result["output"], output)
        self.assertEqual(result["workspace"], workspace)
        self.assertIn(output, self.hypr_monitors())
        creation = self.call_index(["hyprctl", "output", "create", "headless", output])
        # The wait ends where focus is handed back, so the polls that belong to
        # it are the `monitors` queries between creation and that restore.
        restore = self.call_index(["hyprctl", "dispatch", "focusmonitor", "DP-1"])
        polls = [
            index
            for index, command in enumerate(self.hyprctl_calls())
            if command[:2] == ["hyprctl", "monitors"] and creation < index < restore
        ]
        self.assertGreater(
            len(polls), 1, "the missing output was never asked about again"
        )

    def test_stage_creation_fails_when_the_output_never_appears(self) -> None:
        # A compositor that accepts `output create` and produces nothing must
        # not leave a recorded stage, a stolen focus, or a phantom name behind.
        self.write_hypr_state(create_hidden_polls=10_000)
        session = self.begin()
        output, _ = self.stage_names(session)

        result = self.run_cli("stage", "--session", session)

        self.assertEqual(result.returncode, 1)
        self.assertIn("did not create the staging output", result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())
        self.assertNotIn(output, self.hypr_monitors())
        self.assertIn(["hyprctl", "dispatch", "focusmonitor", "DP-1"], self.commands())
        self.assertFalse(self.cli("status", "--session", session)["stage"])
        self.assertNotIn("stage", json.loads(self.session_file(session).read_text()))

    def test_stage_waits_for_a_workspace_adopted_a_poll_later(self) -> None:
        # A brand new output reports an ordinary workspace until the rule
        # takes, so adoption has to be waited for rather than sampled once.
        self.write_hypr_state(create_workspace_polls=3)
        session = self.begin()
        output, workspace = self.stage_names(session)

        result = self.cli("stage", "--session", session)

        self.assertEqual(result["workspace"], workspace)
        # The workspace wait is everything after focus is handed back, which is
        # the last thing the output wait does.
        restore = self.call_index(["hyprctl", "dispatch", "focusmonitor", "DP-1"])
        polls = [
            index
            for index, command in enumerate(self.hyprctl_calls())
            if command[:2] == ["hyprctl", "monitors"] and index > restore
        ]
        self.assertGreater(
            len(polls), 1, "the unadopted workspace was never asked about again"
        )
        self.assertEqual(self.cli("capture", "--session", session)["target"], "stage")
        self.assertIn(output, self.hypr_monitors())

    def test_stage_launch_dispatches_through_hyprland(self) -> None:
        session = self.begin()
        output, workspace = self.stage_names(session)
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)

        launch = self.cli(
            "launch",
            "--session",
            session,
            "--wait-seconds",
            "0",
            "--",
            str(helper),
        )
        try:
            self.assertEqual(launch["spawn"], "stage")
            self.assertEqual(launch["stage"], output)
            dispatch = next(
                command
                for command in self.hyprctl_calls()
                if command[:3] == ["hyprctl", "dispatch", "exec"]
            )
            self.assertTrue(
                dispatch[3].startswith(f"[workspace name:{workspace} silent"),
                dispatch[3],
            )
            self.assertIn("noinitialfocus", dispatch[3])
            recorded = self.eventually(
                lambda: pid_file.read_text() if pid_file.exists() else "",
                "the staged process never reported its pid",
            )
            self.assertEqual(int(recorded), launch["pid"])
        finally:
            self.cli("end", "--session", session)

    def test_stage_launch_arguments_are_never_shell_evaluated(self) -> None:
        session = self.begin()
        pid_file = self.root / "argv-pid"
        argv_file = self.root / "argv"
        marker = self.root / "pwned"
        helper = self.sleeper("argv-app", pid_file, argv_file)
        arguments = [
            "hello world",
            "$HOME",
            "a;b",
            "*",
            "`id`",
            f"$(touch {marker})",
            # A single quote is the only character `shlex.quote` genuinely has
            # to escape. Without one of these, quoting an argument as
            # "'" + argument + "'" would pass every assertion below while
            # letting an apostrophe close the quote and start a new command --
            # so this one really does run `touch` under naive quoting.
            f"x' & touch {marker} & echo '",
            "it's",
            # Hyprland ends the exec rule block at the first "]", so an
            # argument carrying one must never be read as that boundary.
            "]",
            "] /bin/sh -c 'x' #",
            # argparse's REMAINDER has to hand these through untouched.
            "--",
            "",
            # Only representable because the helper records NUL-separated.
            "first line\nsecond line",
        ]

        self.cli(
            "launch",
            "--session",
            session,
            "--wait-seconds",
            "0",
            "--",
            str(helper),
            *arguments,
        )
        try:
            self.eventually(
                lambda: pid_file.exists(),
                "the staged process never reported its pid",
            )
            self.assertFalse(marker.exists(), "an argument reached a shell")
            self.assertEqual(self.recorded_argv(argv_file), arguments)
        finally:
            self.cli("end", "--session", session)

    def test_launch_waits_for_a_window_that_maps_a_poll_later(self) -> None:
        session = self.begin()
        _, workspace = self.stage_names(session)
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xlate",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                    "workspace": {"id": -13, "name": workspace},
                }
            ]
        )
        # A window is never mapped at the instant its process starts, so the
        # first `clients` query legitimately reports nothing.
        self.patch_hypr_state(client_hidden_polls=3)

        launch = self.cli(
            "launch", "--session", session, "--wait-seconds", "10", "--", str(helper)
        )
        try:
            self.assertIsNotNone(launch["window"], "the window was never seen")
            self.assertEqual(launch["window"]["address"], "0xlate")
            self.assertNotIn("warning", launch)
            queries = [
                command
                for command in self.hyprctl_calls()
                if command[:2] == ["hyprctl", "clients"]
            ]
            self.assertGreater(
                len(queries), 1, "the unmapped window was never asked about again"
            )
        finally:
            self.cli("end", "--session", session)

    def test_stage_launch_is_terminated_with_its_children_on_end(self) -> None:
        session = self.begin()
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)

        launch = self.cli(
            "launch",
            "--session",
            session,
            "--wait-seconds",
            "0",
            "--",
            str(helper),
        )
        self.eventually(
            lambda: pid_file.exists(), "the staged process never reported its pid"
        )
        child = int(self.child_pid_file(pid_file).read_text())
        # Hyprland leaves staged processes inside the compositor's process
        # group, so the pid must never be treated as a group of its own.
        self.assertNotEqual(os.getpgid(launch["pid"]), launch["pid"])

        result = self.cli("end", "--session", session)

        self.assertEqual(result["terminated"], 1)
        self.assertTrue(result["stage_removed"])
        self.eventually(
            lambda: self.reaped(launch["pid"]),
            "the staged process survived cleanup",
        )
        self.eventually(
            lambda: self.reaped(child),
            "the staged process left a child behind",
        )

    def test_stage_launch_survives_a_recycled_pid_guard(self) -> None:
        session = self.begin()
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)
        launch = self.cli(
            "launch",
            "--session",
            session,
            "--wait-seconds",
            "0",
            "--",
            str(helper),
        )
        self.eventually(
            lambda: pid_file.exists(), "the staged process never reported its pid"
        )
        path = self.runtime / "screen-verify" / session / "session.json"
        data = json.loads(path.read_text())
        data["processes"][0]["start_time"] = "1"
        path.write_text(json.dumps(data))

        result = self.cli("end", "--session", session)

        self.assertEqual(result["terminated"], 0)
        self.assertFalse(self.reaped(launch["pid"]))
        os.kill(launch["pid"], 15)
        os.kill(int(self.child_pid_file(pid_file).read_text()), 15)

    def test_a_process_named_with_a_space_records_its_real_start_time(self) -> None:
        session = self.begin()
        pid_file = self.root / "spaced-pid"
        # /proc/<pid>/stat carries the process name in parentheses, and a space
        # inside it shifts every field that follows.
        helper = self.sleeper("staged app", pid_file)

        launch = self.cli(
            "launch",
            "--session",
            session,
            "--no-stage",
            "--wait-seconds",
            "0",
            "--",
            str(helper),
        )
        try:
            stat = Path(f"/proc/{launch['pid']}/stat").read_text(encoding="utf-8")
            self.assertIn("(staged app)", stat)
            recorded = json.loads(self.session_file(session).read_text())["processes"]
            self.assertEqual(
                recorded[0]["start_time"], stat.rsplit(")", 1)[1].split()[19]
            )
            self.assertNotEqual(recorded[0]["start_time"], "0")
        finally:
            self.cli("end", "--session", session)

    def test_a_stale_start_time_of_zero_never_kills_a_staged_tree(self) -> None:
        session = self.begin()
        pid_file = self.root / "staged-pid"
        # A name with a space used to make every start time read as "0", so a
        # recycled pid matched its record and `end` signalled the whole tree.
        helper = self.sleeper("staged app", pid_file)
        launch = self.cli(
            "launch",
            "--session",
            session,
            "--wait-seconds",
            "0",
            "--",
            str(helper),
        )
        self.eventually(
            lambda: pid_file.exists(), "the staged process never reported its pid"
        )
        child = int(self.child_pid_file(pid_file).read_text())
        path = self.session_file(session)
        data = json.loads(path.read_text())
        data["processes"][0]["start_time"] = "0"
        path.write_text(json.dumps(data))

        result = self.cli("end", "--session", session)

        self.assertEqual(result["terminated"], 0)
        self.assertFalse(self.reaped(launch["pid"]))
        self.assertFalse(self.reaped(child))
        os.kill(launch["pid"], 15)
        os.kill(child, 15)

    def test_capture_defaults_to_the_stage_output_when_one_exists(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)

        result = self.cli("capture", "--session", session)

        self.assertEqual(result["target"], "stage")
        grim = next(
            command for command in reversed(self.commands()) if command[0] == "grim"
        )
        self.assertEqual(grim[1:-1], ["-o", output])

    def test_capture_defaults_to_the_focused_monitor_without_a_stage(self) -> None:
        session = self.begin()

        result = self.cli("capture", "--session", session)

        self.assertEqual(result["target"], "focused")
        grim = next(
            command for command in reversed(self.commands()) if command[0] == "grim"
        )
        self.assertEqual(grim[1:-1], ["-o", "DP-1"])

    def test_window_target_under_a_stage_uses_the_owned_window(self) -> None:
        session = self.begin()
        _, workspace = self.stage_names(session)
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xstaged",
                    "pid_file": str(pid_file),
                    "at": [100, 200],
                    "size": [640, 480],
                    "workspace": {"id": -13, "name": workspace},
                }
            ]
        )

        launch = self.cli(
            "launch",
            "--session",
            session,
            "--wait-seconds",
            "10",
            "--",
            str(helper),
        )
        try:
            self.assertEqual(launch["window"]["address"], "0xstaged")
            self.assertNotIn("warning", launch)

            self.cli("capture", "--session", session, "--target", "window")

            grim = next(
                command for command in reversed(self.commands()) if command[0] == "grim"
            )
            self.assertEqual(grim[1:-1], ["-g", "100,200 640x480"])
        finally:
            self.cli("end", "--session", session)

    def test_window_target_skips_owned_windows_that_have_closed(self) -> None:
        session = self.begin()
        first_pid = self.root / "first-pid"
        second_pid = self.root / "second-pid"
        first = self.sleeper("first-app", first_pid)
        second = self.sleeper("second-app", second_pid)
        older = {
            "address": "0xfirst",
            "pid_file": str(first_pid),
            "at": [11, 12],
            "size": [300, 400],
        }
        newer = {
            "address": "0xsecond",
            "pid_file": str(second_pid),
            "at": [21, 22],
            "size": [500, 600],
        }
        self.set_clients([older])
        self.cli(
            "launch", "--session", session, "--wait-seconds", "10", "--", str(first)
        )
        self.set_clients([older, newer])
        launch = self.cli(
            "launch", "--session", session, "--wait-seconds", "10", "--", str(second)
        )
        self.assertEqual(launch["window"]["address"], "0xsecond")
        try:
            # The newest owned window closes; the older one is still open.
            self.set_clients([older])

            self.cli("capture", "--session", session, "--target", "window")

            grim = next(
                command for command in reversed(self.commands()) if command[0] == "grim"
            )
            self.assertEqual(grim[1:-1], ["-g", "11,12 300x400"])
        finally:
            self.cli("end", "--session", session)

    def test_window_target_never_falls_back_to_the_user_window(self) -> None:
        session = self.begin()
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xstaged",
                    "pid_file": str(pid_file),
                    "at": [100, 200],
                    "size": [640, 480],
                }
            ]
        )
        self.cli(
            "launch", "--session", session, "--wait-seconds", "10", "--", str(helper)
        )
        try:
            self.set_clients([])

            result = self.run_cli(
                "capture", "--session", session, "--target", "window"
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("still open", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            geometries = [
                command
                for command in self.commands()
                if command[0] == "grim" and "10,20 800x600" in command
            ]
            self.assertEqual(geometries, [])
        finally:
            self.cli("end", "--session", session)

    def test_window_target_refuses_when_the_stage_owns_no_window(self) -> None:
        session = self.begin()
        self.cli("stage", "--session", session)

        result = self.run_cli("capture", "--session", session, "--target", "window")

        self.assertEqual(result.returncode, 1)
        self.assertIn("still open", result.stderr)
        self.assertEqual(
            [
                command
                for command in self.commands()
                if command[0] == "grim" and "10,20 800x600" in command
            ],
            [],
        )

    def test_window_target_refuses_after_a_layer_adapter(self) -> None:
        session = self.begin()
        self.sleeper("rofi", self.root / "rofi-pid")
        self.cli("adapter", "--session", session, "--wait-seconds", "0", "rofi")
        try:
            result = self.run_cli(
                "capture", "--session", session, "--target", "window"
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("still open", result.stderr)
            self.assertEqual(
                [
                    command
                    for command in self.commands()
                    if command[0] == "grim" and "10,20 800x600" in command
                ],
                [],
            )
        finally:
            self.cli("end", "--session", session)

    def test_capture_falls_back_to_focused_when_the_stage_output_vanished(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        self.drop_fake_monitor(output)

        result = self.cli("capture", "--session", session)

        self.assertEqual(result["target"], "focused")
        grim = next(
            command for command in reversed(self.commands()) if command[0] == "grim"
        )
        self.assertEqual(grim[1:-1], ["-o", "DP-1"])
        # An explicit request for the stage must still fail loudly.
        explicit = self.run_cli(
            "capture", "--session", session, "--target", "stage"
        )
        self.assertEqual(explicit.returncode, 1)

    def test_end_reports_kept_windows_it_could_not_rescue(self) -> None:
        session = self.begin()
        output, workspace = self.stage_names(session)
        pid_file = self.root / "kept-pid"
        helper = self.sleeper("kept-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xkept",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                    "workspace": {"id": -13, "name": workspace},
                }
            ]
        )
        launch = self.cli(
            "launch",
            "--keep-open",
            "--session",
            session,
            "--wait-seconds",
            "10",
            "--",
            str(helper),
        )
        try:
            # No real monitor is left to hand the window back to.
            self.drop_fake_monitor("DP-1")

            result = self.cli("end", "--session", session)

            self.assertIn("could not be moved", result["warning"])
            self.assertEqual(
                [
                    command
                    for command in self.hyprctl_calls()
                    if command[1:3] == ["dispatch", "movetoworkspacesilent"]
                ],
                [],
            )
        finally:
            os.kill(launch["pid"], 15)
            os.kill(int(self.child_pid_file(pid_file).read_text()), 15)

    def test_end_reports_kept_windows_it_could_not_ask_about(self) -> None:
        session = self.begin()
        _, workspace = self.stage_names(session)
        pid_file = self.root / "kept-pid"
        helper = self.sleeper("kept-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xkept",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                    "workspace": {"id": -13, "name": workspace},
                }
            ]
        )
        launch = self.cli(
            "launch",
            "--keep-open",
            "--session",
            session,
            "--wait-seconds",
            "10",
            "--",
            str(helper),
        )
        try:
            # The window is already recorded, so only `end` is left unable to
            # ask. "No kept window is on the stage" and "that query failed" are
            # different answers, and the output is removed either way.
            self.environment["FAKE_HYPRCTL_FAIL"] = "clients"

            result = self.cli("end", "--session", session)

            self.assertIn("could not be moved", result["warning"])
            self.assertEqual(
                [
                    command
                    for command in self.hyprctl_calls()
                    if command[1:3] == ["dispatch", "movetoworkspacesilent"]
                ],
                [],
            )
        finally:
            os.kill(launch["pid"], 15)
            os.kill(int(self.child_pid_file(pid_file).read_text()), 15)

    def test_a_negative_rescue_workspace_is_never_dispatched(self) -> None:
        session = self.begin()
        _, workspace = self.stage_names(session)
        # Hyprland reads a leading "-" as a relative shift, so the negative id
        # of a special workspace would move the window somewhere unintended.
        self.write_hypr_state(
            monitors=[
                {
                    "name": "DP-1",
                    "focused": True,
                    "width": 2560,
                    "height": 1440,
                    "scale": 1.25,
                    "activeWorkspace": {"id": -13, "name": "special:magic"},
                }
            ]
        )
        pid_file = self.root / "kept-pid"
        helper = self.sleeper("kept-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xkept",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                    "workspace": {"id": -13, "name": workspace},
                }
            ]
        )
        launch = self.cli(
            "launch",
            "--keep-open",
            "--session",
            session,
            "--wait-seconds",
            "10",
            "--",
            str(helper),
        )
        try:
            result = self.cli("end", "--session", session)

            self.assertIn("could not be moved", result["warning"])
            self.assertEqual(
                [
                    command
                    for command in self.hyprctl_calls()
                    if command[1:3] == ["dispatch", "movetoworkspacesilent"]
                ],
                [],
            )
        finally:
            os.kill(launch["pid"], 15)
            os.kill(int(self.child_pid_file(pid_file).read_text()), 15)

    def test_end_leaves_kept_windows_that_never_reached_the_stage(self) -> None:
        session = self.begin()
        pid_file = self.root / "stray-pid"
        helper = self.sleeper("stray-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xstray",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                    "workspace": {"id": 1, "name": "1"},
                }
            ]
        )
        launch = self.cli(
            "launch",
            "--keep-open",
            "--session",
            session,
            "--wait-seconds",
            "10",
            "--",
            str(helper),
        )
        try:
            # The launch-time sweep may already have tried to pull the stray
            # onto the stage; what `end` itself dispatches is the property
            # under test, so only the commands it issues are inspected.
            before = len(self.commands())

            result = self.cli("end", "--session", session)

            self.assertNotIn("warning", result)
            self.assertEqual(
                [
                    command
                    for command in self.commands()[before:]
                    if command[1:3] == ["dispatch", "movetoworkspacesilent"]
                ],
                [],
            )
        finally:
            os.kill(launch["pid"], 15)
            os.kill(int(self.child_pid_file(pid_file).read_text()), 15)

    def test_a_tampered_stage_output_never_reaches_a_real_monitor(self) -> None:
        session = self.begin()
        output, workspace = self.stage_names(session)
        self.cli("stage", "--session", session)
        self.tamper(session, output="DP-1", workspace=workspace)

        capture = self.run_cli("capture", "--session", session)
        status = self.run_cli("status", "--session", session)

        self.assertEqual(capture.returncode, 1)
        self.assertIn("foreign stage record", capture.stderr)
        self.assertEqual(status.returncode, 1)
        self.assertEqual(
            [
                command
                for command in self.commands()
                if command[0] == "grim" and "DP-1" in command
            ],
            [],
        )

        result = self.cli("end", "--session", session)

        self.assertTrue(result["stage_removed"])
        self.assertNotIn(["hyprctl", "output", "remove", "DP-1"], self.commands())
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())
        self.assertEqual(self.hypr_monitors(), ["DP-1"])

    def test_end_reclaims_the_derived_output_after_the_record_is_lost(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        # A stage whose record never survived its creation still owns a real
        # monitor, and the derived name is the only one it can ever have used.
        path = self.session_file(session)
        data = json.loads(path.read_text())
        data.pop("stage")
        path.write_text(json.dumps(data))

        result = self.cli("end", "--session", session)

        self.assertFalse(result["stage_removed"])
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())
        self.assertEqual(self.hypr_monitors(), ["DP-1"])

    def test_end_rescues_a_kept_window_whose_workspace_is_unreported(self) -> None:
        session = self.begin()
        pid_file = self.root / "kept-pid"
        helper = self.sleeper("kept-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xkept",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                }
            ]
        )
        launch = self.cli(
            "launch",
            "--keep-open",
            "--session",
            session,
            "--wait-seconds",
            "10",
            "--",
            str(helper),
        )
        try:
            result = self.cli("end", "--session", session)

            self.assertIn("kept window", result["warning"])
            self.assertIn(
                ["hyprctl", "dispatch", "movetoworkspacesilent", "1,address:0xkept"],
                self.commands(),
            )
        finally:
            os.kill(launch["pid"], 15)
            os.kill(int(self.child_pid_file(pid_file).read_text()), 15)

    def test_end_hands_kept_stage_windows_back_before_removing_the_output(self) -> None:
        session = self.begin()
        output, workspace = self.stage_names(session)
        pid_file = self.root / "kept-pid"
        helper = self.sleeper("kept-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xkept",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                    "workspace": {"id": -13, "name": workspace},
                }
            ]
        )
        launch = self.cli(
            "launch",
            "--keep-open",
            "--session",
            session,
            "--wait-seconds",
            "10",
            "--",
            str(helper),
        )
        try:
            result = self.cli("end", "--session", session)

            self.assertEqual(result["terminated"], 0)
            self.assertIn("kept window", result["warning"])
            moved = self.call_index(
                [
                    "hyprctl",
                    "dispatch",
                    "movetoworkspacesilent",
                    "1,address:0xkept",
                ]
            )
            removed = self.call_index(["hyprctl", "output", "remove", output])
            self.assertLess(moved, removed)
            self.assertFalse(self.reaped(launch["pid"]))
        finally:
            os.kill(launch["pid"], 15)
            os.kill(int(self.child_pid_file(pid_file).read_text()), 15)

    def test_purge_reclaims_the_output_of_an_unreadable_session(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        path = self.runtime / "screen-verify" / session
        self.session_file(session).write_text("{ not json")
        old_time = time.time() - 25 * 60 * 60
        os.utime(path, (old_time, old_time))

        self.begin()

        self.assertFalse(path.exists())
        self.assertNotIn(output, self.hypr_monitors())
        audit = (self.state / "screen-verify/audit.jsonl").read_text()
        self.assertIn('"outcome":"unreadable"', audit)

    def test_purge_leaves_a_directory_that_is_not_a_session(self) -> None:
        self.begin()
        # Only a session-shaped name can name an output of ours, and nothing
        # else under the runtime root is ours to delete either.
        stray = self.runtime / "screen-verify" / "not-a-session"
        stray.mkdir(mode=0o700)
        (stray / "keep").write_text("private")
        # A parseable session file does not make a foreign directory ours
        # either: the name is what decides, on both paths.
        readable = self.runtime / "screen-verify" / "also-not-a-session"
        readable.mkdir(mode=0o700)
        (readable / "session.json").write_text(
            json.dumps(
                {
                    "session": "also-not-a-session",
                    "started_at": "2020-01-01T00:00:00+00:00",
                    "mode": "dark",
                    "captures": 0,
                    "processes": [],
                }
            )
        )
        old_time = time.time() - 25 * 60 * 60
        os.utime(stray, (old_time, old_time))
        os.utime(readable, (old_time, old_time))

        self.begin()

        self.assertTrue(stray.is_dir())
        self.assertEqual((stray / "keep").read_text(), "private")
        self.assertTrue(readable.is_dir())
        self.assertEqual(
            json.loads((readable / "session.json").read_text())["session"],
            "also-not-a-session",
        )
        self.assertEqual(
            [
                command
                for command in self.commands()
                if command[:3] == ["hyprctl", "output", "remove"]
            ],
            [],
        )
        audit = (self.state / "screen-verify/audit.jsonl").read_text()
        self.assertIn('"outcome":"skipped"', audit)

    def test_purge_reclaims_the_output_even_when_previews_cannot_restore(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        self.quiet_gsettings()
        self.cli(
            "preview",
            "gsettings",
            "--session",
            session,
            "--schema",
            "org.example",
            "--key",
            "theme",
            "--value",
            "'preview'",
        )
        self.failing_gsettings()
        path = self.runtime / "screen-verify" / session
        old_time = time.time() - 25 * 60 * 60
        os.utime(path, (old_time, old_time))

        self.begin()

        self.assertTrue(path.exists())
        self.assertNotIn(output, self.hypr_monitors())
        self.assertNotIn("stage", json.loads(self.session_file(session).read_text()))
        audit = (self.state / "screen-verify/audit.jsonl").read_text()
        self.assertIn('"outcome":"restore-failed"', audit)

        os.utime(path, (old_time, old_time))
        self.begin()

        # The derived name is reclaimed on every purge, so retrying it is
        # harmless; what must never happen is a removal aimed anywhere else.
        removals = [
            command
            for command in self.commands()
            if command[:3] == ["hyprctl", "output", "remove"]
        ]
        self.assertEqual({command[3] for command in removals}, {output})
        self.assertEqual(self.hypr_monitors(), ["DP-1"])

    def test_a_tampered_stage_workspace_is_rejected_before_any_dispatch(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        marker = self.root / "pwned"
        helper = self.sleeper("staged-app", self.root / "staged-pid")
        self.cli("stage", "--session", session)
        self.tamper(
            session,
            output=output,
            workspace=f"x] /bin/sh -c 'touch {marker}' #",
        )

        result = self.run_cli(
            "launch", "--session", session, "--wait-seconds", "0", "--", str(helper)
        )

        self.assertFalse(marker.exists(), "the tampered rule reached a shell")
        self.assertEqual(
            [
                command
                for command in self.hyprctl_calls()
                if command[:3] == ["hyprctl", "dispatch", "exec"]
            ],
            [],
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("foreign stage record", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_an_incomplete_stage_record_fails_cleanly(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        helper = self.sleeper("staged-app", self.root / "staged-pid")
        self.cli("stage", "--session", session)
        self.tamper(session, output=output)

        result = self.run_cli(
            "launch", "--session", session, "--wait-seconds", "0", "--", str(helper)
        )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(
            result.stderr.strip(),
            "screen-verify: The session holds an unusable stage record",
        )

    def test_launch_warns_when_the_window_misses_the_staging_workspace(self) -> None:
        session = self.begin()
        pid_file = self.root / "stray-pid"
        helper = self.sleeper("stray-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xstray",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [10, 10],
                    "workspace": {"id": 1, "name": "1"},
                }
            ]
        )

        launch = self.cli(
            "launch", "--session", session, "--wait-seconds", "10", "--", str(helper)
        )
        try:
            self.assertIn("staging workspace", launch["warning"])
            # The warning describes what the sweep could not fix, never what
            # it did not try: the fake ignores the move, so the window is
            # still off the stage after a real recovery attempt.
            _, workspace = self.stage_names(session)
            self.assertIn(
                [
                    "hyprctl",
                    "dispatch",
                    "movetoworkspacesilent",
                    f"name:{workspace},address:0xstray",
                ],
                self.commands(),
            )
        finally:
            self.cli("end", "--session", session)

    def test_stage_launch_exports_the_session_marker_to_the_tree(self) -> None:
        session = self.begin()
        pid_file = self.root / "marked-pid"
        helper = self.sleeper("marked-app", pid_file)

        launch = self.cli(
            "launch", "--session", session, "--wait-seconds", "0", "--", str(helper)
        )
        try:
            dispatch = next(
                command
                for command in self.hyprctl_calls()
                if command[:3] == ["hyprctl", "dispatch", "exec"]
            )
            self.assertIn(f"export SCREEN_VERIFY_STAGE={session}; ", dispatch[3])
            self.eventually(
                lambda: pid_file.exists(), "the staged process never reported its pid"
            )
            marker = f"SCREEN_VERIFY_STAGE={session}".encode()
            # The exec'd application itself carries the marker...
            environ = Path(f"/proc/{launch['pid']}/environ").read_bytes()
            self.assertIn(marker, environ.split(b"\0"))
            # ...and so does its child, which is what makes ownership testable
            # after a descendant double-forks out of the pid tree.
            child = int(self.child_pid_file(pid_file).read_text())
            child_environ = Path(f"/proc/{child}/environ").read_bytes()
            self.assertIn(marker, child_environ.split(b"\0"))
        finally:
            self.cli("end", "--session", session)

    def test_launch_sweeps_a_leaked_child_window_onto_the_stage(self) -> None:
        session = self.begin()
        _, workspace = self.stage_names(session)
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)
        # The primary window landed on the stage; a child's window mapped on
        # the user's own workspace after the one-shot exec rule was consumed.
        self.set_clients(
            [
                {
                    "address": "0xmain",
                    "pid_file": str(pid_file),
                    "at": [0, 0],
                    "size": [100, 100],
                    "workspace": {"id": -13, "name": workspace},
                },
                {
                    "address": "0xleak",
                    "pid_file": str(self.child_pid_file(pid_file)),
                    "at": [840, 65],
                    "size": [950, 950],
                    "workspace": {"id": 4, "name": "4"},
                },
                # The user's own window shares that workspace; being off the
                # stage is never enough to move a window nobody here owns.
                {
                    "address": "0xbystander",
                    "pid": 1,
                    "at": [0, 0],
                    "size": [200, 200],
                    "workspace": {"id": 4, "name": "4"},
                },
            ]
        )

        launch = self.cli(
            "launch", "--session", session, "--wait-seconds", "10", "--", str(helper)
        )
        try:
            self.assertEqual(launch["window"]["address"], "0xmain")
            # The primary window sits on the stage, so the leaked child must
            # not surface as a warning about the launch itself.
            self.assertNotIn("warning", launch)
            moves = [
                command
                for command in self.hyprctl_calls()
                if command[1:3] == ["dispatch", "movetoworkspacesilent"]
            ]
            self.assertIn(
                [
                    "hyprctl",
                    "dispatch",
                    "movetoworkspacesilent",
                    f"name:{workspace},address:0xleak",
                ],
                moves,
            )
            # A window already on the stage is never re-dispatched, and an
            # unowned window is never swept however far off the stage it is.
            self.assertEqual(
                [
                    command
                    for command in moves
                    if "0xmain" in command[3] or "0xbystander" in command[3]
                ],
                [],
            )
        finally:
            self.cli("end", "--session", session)

    def test_ensure_stage_starts_and_records_one_watcher(self) -> None:
        self.enable_socket2()
        session = self.begin()

        self.cli("stage", "--session", session)

        watcher = self.watcher_record(session)
        self.assertIsInstance(watcher["pid"], int)
        self.assertIsInstance(watcher["start_time"], str)
        self.accept_watcher()
        self.assertFalse(self.reaped(watcher["pid"]))
        # Re-entering the stage keeps the live watcher instead of stacking a
        # second one next to it.
        self.cli("stage", "--session", session)
        self.assertEqual(self.watcher_record(session), watcher)
        self.socket2.settimeout(1.0)
        with self.assertRaises(socket.timeout):
            self.socket2.accept()

        self.cli("end", "--session", session)

        self.eventually(
            lambda: self.reaped(watcher["pid"]), "the watcher survived end"
        )

    def test_the_watcher_moves_an_escaped_owned_window(self) -> None:
        self.enable_socket2()
        session = self.begin()
        _, workspace = self.stage_names(session)
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)

        self.cli(
            "launch", "--session", session, "--wait-seconds", "0", "--", str(helper)
        )
        try:
            connection = self.accept_watcher()
            self.eventually(
                lambda: pid_file.exists(), "the staged process never reported its pid"
            )
            # Two owned windows and one belonging to another process open on
            # the user's workspace after launch. socket2 emits addresses
            # without the 0x prefix that `clients` and `dispatch` carry.
            self.set_clients(
                [
                    {
                        "address": "0xaaa1",
                        "pid_file": str(pid_file),
                        "at": [0, 0],
                        "size": [10, 10],
                        "workspace": {"id": 4, "name": "4"},
                    },
                    {
                        "address": "0xbbb2",
                        "pid": 1,
                        "at": [0, 0],
                        "size": [10, 10],
                        "workspace": {"id": 4, "name": "4"},
                    },
                    {
                        "address": "0xccc3",
                        "pid_file": str(self.child_pid_file(pid_file)),
                        "at": [0, 0],
                        "size": [10, 10],
                        "workspace": {"id": 4, "name": "4"},
                    },
                ]
            )
            connection.sendall(
                b"openwindow>>aaa1,4,imgpreview_x,preview\n"
                b"openwindow>>bbb2,4,SecretApp,Secret Document\n"
                b"openwindow>>ccc3,4,imgpreview_y,preview\n"
            )
            expected = [
                "hyprctl",
                "dispatch",
                "movetoworkspacesilent",
                f"name:{workspace},address:0xccc3",
            ]
            # The events are handled in order, so once the last one has been
            # acted on the middle one has provably been decided too.
            self.eventually(
                lambda: expected in self.commands(),
                "the watcher never moved the escaped window",
            )
            self.assertIn(
                [
                    "hyprctl",
                    "dispatch",
                    "movetoworkspacesilent",
                    f"name:{workspace},address:0xaaa1",
                ],
                self.commands(),
            )
            # The unowned window between them was left exactly where it was.
            self.assertEqual(
                [
                    command
                    for command in self.hyprctl_calls()
                    if command[1:3] == ["dispatch", "movetoworkspacesilent"]
                    and "0xbbb2" in command[3]
                ],
                [],
            )
            # A stream read owes nothing to line boundaries: an event split
            # across two sends — and, with the pause, almost certainly two
            # recvs — must be reassembled, not acted on early or dropped.
            self.set_clients(
                [
                    {
                        "address": "0xddd4",
                        "pid_file": str(pid_file),
                        "at": [0, 0],
                        "size": [10, 10],
                        "workspace": {"id": 4, "name": "4"},
                    }
                ]
            )
            connection.sendall(b"openwindow>>ddd4,4,ueber")
            time.sleep(0.3)
            connection.sendall(b"zugpp_z,preview\n")
            split = [
                "hyprctl",
                "dispatch",
                "movetoworkspacesilent",
                f"name:{workspace},address:0xddd4",
            ]
            self.eventually(
                lambda: split in self.commands(),
                "the split event was never reassembled",
            )
        finally:
            self.cli("end", "--session", session)

    def test_the_watcher_exits_when_the_session_disappears(self) -> None:
        self.enable_socket2()
        session = self.begin()
        self.cli("stage", "--session", session)
        watcher = self.watcher_record(session)
        self.accept_watcher()
        self.assertFalse(self.reaped(watcher["pid"]))

        # Nothing signals it: the session directory is simply gone, as after
        # a crash, and the watcher has to notice that by itself.
        shutil.rmtree(self.runtime / "screen-verify" / session)

        self.eventually(
            lambda: self.reaped(watcher["pid"]),
            "the watcher outlived its session",
        )

    def test_end_terminates_the_recorded_watcher(self) -> None:
        session = self.begin()
        self.cli("stage", "--session", session)
        # Without a socket the real watcher exits at once; a stand-in process
        # recorded in its place proves `end` signals what the record names.
        decoy = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
        try:
            stat = Path(f"/proc/{decoy.pid}/stat").read_text(encoding="utf-8")
            path = self.session_file(session)
            data = json.loads(path.read_text())
            data["stage"]["watcher"] = {
                "pid": decoy.pid,
                "start_time": stat.rsplit(")", 1)[1].split()[19],
            }
            path.write_text(json.dumps(data))

            self.cli("end", "--session", session)

            self.eventually(
                lambda: decoy.poll() is not None, "the watcher was never signalled"
            )
        finally:
            decoy.kill()
            decoy.wait()

    def test_end_never_signals_a_recycled_watcher_pid(self) -> None:
        session = self.begin()
        self.cli("stage", "--session", session)
        # The recorded pid now names a process that was never the watcher, so
        # the start-time guard must keep `end`'s SIGTERM away from it.
        bystander = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(30)"]
        )
        try:
            path = self.session_file(session)
            data = json.loads(path.read_text())
            data["stage"]["watcher"] = {"pid": bystander.pid, "start_time": "1"}
            path.write_text(json.dumps(data))

            self.cli("end", "--session", session)

            time.sleep(0.3)
            self.assertIsNone(bystander.poll(), "a recycled pid was signalled")
        finally:
            bystander.kill()
            bystander.wait()

    def test_end_removes_the_stage_output_and_reports_it(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        status = self.cli("status", "--session", session)
        self.assertTrue(status["stage"])
        self.assertEqual(status["stage_output"], output)

        result = self.cli("end", "--session", session)

        self.assertTrue(result["stage_removed"])
        self.assertNotIn(output, self.hypr_monitors())
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())

    def test_purge_removes_the_stage_output_of_an_abandoned_session(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        path = self.runtime / "screen-verify" / session
        old_time = time.time() - 25 * 60 * 60
        os.utime(path, (old_time, old_time))

        self.begin()

        self.assertFalse(path.exists())
        self.assertNotIn(output, self.hypr_monitors())
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())

    def test_window_adapter_launches_onto_the_stage(self) -> None:
        session = self.begin()
        output, workspace = self.stage_names(session)
        pid_file = self.root / "foot-pid"
        argv_file = self.root / "foot-argv"
        self.sleeper("foot", pid_file, argv_file)

        result = self.cli(
            "adapter", "--session", session, "--wait-seconds", "0", "foot"
        )
        try:
            self.assertEqual(result["spawn"], "stage")
            self.assertEqual(result["stage"], output)
            self.assertNotIn("warning", result)
            dispatch = next(
                command
                for command in self.hyprctl_calls()
                if command[:3] == ["hyprctl", "dispatch", "exec"]
            )
            self.assertIn(f"[workspace name:{workspace} silent", dispatch[3])
            self.eventually(
                lambda: pid_file.exists(), "the foot adapter never started"
            )
            self.assertEqual(
                self.recorded_argv(argv_file),
                ["--app-id=screen-verify-foot"],
            )
        finally:
            self.cli("end", "--session", session)

    def test_desktop_and_notification_adapters_never_create_a_stage(self) -> None:
        session = self.begin()

        self.cli("adapter", "--session", session, "desktop")
        self.cli("adapter", "--session", session, "notification")

        self.assertEqual(
            [command for command in self.hyprctl_calls() if command[1] == "output"], []
        )
        self.assertFalse(self.cli("status", "--session", session)["stage"])

    def test_layer_adapter_opens_on_the_stage_output_with_a_warning(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        pid_file = self.root / "rofi-pid"
        argv_file = self.root / "rofi-argv"
        self.sleeper("rofi", pid_file, argv_file)

        result = self.cli(
            "adapter", "--session", session, "--wait-seconds", "0", "rofi"
        )
        try:
            self.assertEqual(result["adapter"], "rofi")
            self.assertEqual(result["spawn"], "direct")
            self.assertIn("keyboard", result["warning"])
            self.eventually(
                lambda: pid_file.exists(), "the rofi adapter never started"
            )
            self.assertEqual(
                self.recorded_argv(argv_file),
                ["-show", "drun", "-m", output],
            )
            self.assertEqual(
                [
                    command
                    for command in self.hyprctl_calls()
                    if command[:3] == ["hyprctl", "dispatch", "exec"]
                ],
                [],
            )
        finally:
            self.cli("end", "--session", session)

    def test_end_reclaims_the_output_even_when_previews_cannot_restore(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        path = self.runtime / "screen-verify" / session
        self.cli("stage", "--session", session)
        self.quiet_gsettings()
        self.cli(
            "preview",
            "gsettings",
            "--session",
            session,
            "--schema",
            "org.example",
            "--key",
            "theme",
            "--value",
            "'preview'",
        )
        self.failing_gsettings()

        result = self.run_cli("end", "--session", session)

        # The session is retained so the restore can be retried, but a preview
        # that refuses to come back must never strand a headless monitor on the
        # user's compositor for the rest of the day.
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("Traceback", result.stderr)
        self.assertTrue(path.exists())
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())
        self.assertNotIn(output, self.hypr_monitors())

    def test_end_reports_no_removal_when_the_output_survives(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        # `output remove` is fire-and-forget, so a compositor that ignores it
        # must not be reported as a successful removal.
        self.patch_hypr_state(ignore_output_removals=True)

        result = self.cli("end", "--session", session)

        self.assertFalse(result["stage_removed"])
        self.assertIn(["hyprctl", "output", "remove", output], self.commands())
        self.assertIn(output, self.hypr_monitors())

    def test_window_target_refuses_a_recycled_window_address(self) -> None:
        session = self.begin()
        _, workspace = self.stage_names(session)
        pid_file = self.root / "staged-pid"
        helper = self.sleeper("staged-app", pid_file)
        self.set_clients(
            [
                {
                    "address": "0xabc",
                    "pid_file": str(pid_file),
                    "at": [100, 200],
                    "size": [640, 480],
                    "workspace": {"id": -13, "name": workspace},
                }
            ]
        )
        launch = self.cli(
            "launch", "--session", session, "--wait-seconds", "10", "--", str(helper)
        )
        try:
            self.assertEqual(launch["window"]["address"], "0xabc")
            # Hyprland addresses are object pointers and get reused. The same
            # address now belongs to the user's own window, which reports no
            # workspace — so only the recorded pid can tell them apart.
            self.set_clients(
                [
                    {
                        "address": "0xabc",
                        "pid": 1,
                        "at": [0, 0],
                        "size": [2560, 1440],
                    }
                ]
            )

            result = self.run_cli(
                "capture", "--session", session, "--target", "window"
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("still open", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertEqual(
                [
                    command
                    for command in self.commands()
                    if command[0] == "grim" and "0,0 2560x1440" in command
                ],
                [],
            )
        finally:
            self.cli("end", "--session", session)

    def test_window_target_ignores_a_window_launched_off_the_stage(self) -> None:
        session = self.begin()
        desktop_pid = self.root / "desktop-pid"
        desktop = self.sleeper("desktop-app", desktop_pid)
        self.set_clients(
            [
                {
                    "address": "0xdesktop",
                    "pid_file": str(desktop_pid),
                    "at": [5, 6],
                    "size": [700, 800],
                    "workspace": {"id": 1, "name": "1"},
                }
            ]
        )
        self.cli(
            "launch",
            "--session",
            session,
            "--no-stage",
            "--wait-seconds",
            "10",
            "--",
            str(desktop),
        )
        # A later staged launch records no window of its own, so walking back
        # through the session's history would reach the desktop window.
        staged = self.sleeper("staged-app", self.root / "staged-pid")
        self.cli(
            "launch", "--session", session, "--wait-seconds", "0", "--", str(staged)
        )
        try:
            result = self.run_cli(
                "capture", "--session", session, "--target", "window"
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("still open", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertEqual(
                [
                    command
                    for command in self.commands()
                    if command[0] == "grim" and "5,6 700x800" in command
                ],
                [],
            )
        finally:
            self.cli("end", "--session", session)

    def test_capture_refuses_a_stage_that_left_its_workspace(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        # The output still exists but now shows an ordinary workspace, so
        # `grim -o` would come back blank and report success.
        self.set_active_workspace(output, {"id": 9, "name": "9"})
        self.patch_hypr_state(ignore_workspace_moves=True)

        default = self.run_cli("capture", "--session", session)
        explicit = self.run_cli("capture", "--session", session, "--target", "stage")

        self.assertEqual(default.returncode, 1)
        self.assertEqual(explicit.returncode, 1)
        self.assertIn("blank", default.stderr)
        self.assertNotIn("Traceback", default.stderr)
        # Neither a blank stage capture nor a silent fallback onto the user's
        # own monitor is an acceptable outcome.
        self.assertEqual([c for c in self.commands() if c[0] == "grim"], [])

    def test_reentering_a_stage_that_left_its_workspace_fails(self) -> None:
        session = self.begin()
        output, _ = self.stage_names(session)
        self.cli("stage", "--session", session)
        # An output that exists is not a working stage; re-entry must not hand
        # back a record for a stage every capture would find empty.
        self.set_active_workspace(output, {"id": 9, "name": "9"})
        self.patch_hypr_state(ignore_workspace_moves=True)

        result = self.run_cli("stage", "--session", session)

        self.assertEqual(result.returncode, 1)
        self.assertIn("blank", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_capture_reasserts_a_stage_that_drifted_off_its_workspace(self) -> None:
        session = self.begin()
        output, workspace = self.stage_names(session)
        self.cli("stage", "--session", session)
        self.set_active_workspace(output, {"id": 9, "name": "9"})

        result = self.cli("capture", "--session", session)

        self.assertEqual(result["target"], "stage")
        self.assertIn(
            [
                "hyprctl",
                "dispatch",
                "moveworkspacetomonitor",
                f"name:{workspace} {output}",
            ],
            self.commands(),
        )
        grim = next(
            command for command in reversed(self.commands()) if command[0] == "grim"
        )
        self.assertEqual(grim[1:-1], ["-o", output])

    def test_default_capture_refuses_an_unanswerable_stage_query(self) -> None:
        session = self.begin()
        self.cli("stage", "--session", session)
        # "the output is gone" and "that query failed" are different answers:
        # only the first may degrade to the user's own focused monitor.
        self.environment["FAKE_HYPRCTL_FAIL"] = "monitors"

        default = self.run_cli("capture", "--session", session)
        explicit = self.run_cli("capture", "--session", session, "--target", "stage")

        self.assertEqual(default.returncode, 1)
        self.assertEqual(explicit.returncode, 1)
        self.assertNotIn("Traceback", default.stderr)
        self.assertEqual(
            [command for command in self.commands() if command[0] == "grim"], []
        )

    def test_every_command_purges_abandoned_sessions(self) -> None:
        old_session = self.begin()
        old_path = self.runtime / "screen-verify" / old_session
        old_time = time.time() - 25 * 60 * 60
        os.utime(old_path, (old_time, old_time))

        self.cli("status", "--session", old_session, check=False)

        self.assertFalse(old_path.exists())


class StagePlacementFallbackTests(unittest.TestCase):
    """The placement snapshot when the compositor answers badly, or not at all.

    A stage that cannot be placed is worse than useless -- it is placed by
    Hyprland instead, flush against the user's screen -- so no reading of the
    layout may turn into an exception. The CLI-level fake cannot express a
    `monitors` query that fails only at this moment, so this drives the
    functions directly, through the same one-snapshot path the stage uses.
    """

    def snapshot(self, answer: object) -> list[dict]:
        def monitors() -> list[dict]:
            if isinstance(answer, BaseException):
                raise answer
            return answer

        original = stage_module.monitors
        stage_module.monitors = monitors
        try:
            return stage_module.placement_snapshot()
        finally:
            stage_module.monitors = original

    def place(self, answer: object) -> tuple[int, int]:
        position = stage_module.stage_position(self.snapshot(answer), 2560, 1440)
        x, _, y = position.partition("x")
        return int(x), int(y)

    def assert_off_screen(self, corner: tuple[int, int]) -> None:
        self.assertEqual(
            corner,
            (-2560 - stage_module.STAGE_GAP, -1440 - stage_module.STAGE_GAP),
        )
        self.assertLess(corner[0], 0)
        self.assertLess(corner[1], 0)

    def test_a_failed_monitors_query_still_places_the_stage_off_screen(self) -> None:
        self.assert_off_screen(self.place(ScreenError("Command failed: hyprctl")))

    def test_an_unexpected_monitors_failure_never_reaches_the_caller(self) -> None:
        self.assert_off_screen(self.place(TypeError("hyprctl answered nonsense")))

    def test_monitors_without_a_usable_position_are_not_measured_from(self) -> None:
        # A bool is an int in Python, and half a position is no position, so
        # neither entry may be allowed to pull the origin to zero-ish by
        # accident -- the fallback origin has to be reached deliberately.
        self.assert_off_screen(
            self.place(
                [
                    {"name": "DP-1"},
                    {"name": "HDMI-A-1", "x": True, "y": True},
                    {"name": "DP-2", "x": 4000, "y": None},
                ]
            )
        )

    def test_a_failed_query_puts_the_size_and_the_position_on_one_fallback(
        self,
    ) -> None:
        # Size and position come out of the same snapshot, so a layout that
        # could not be read cannot leave one of them measured and the other
        # guessed -- the case where a real origin is negative but the position
        # falls back to 0,0 and parks the stage on a real monitor.
        entries = self.snapshot(ScreenError("Command failed: hyprctl"))
        reference = stage_module.reference_monitor(entries)
        self.assertEqual(reference, stage_module.FALLBACK_MONITOR)
        position = stage_module.stage_position(
            entries, reference["width"], reference["height"]
        )
        gap = stage_module.STAGE_GAP
        self.assertEqual(
            position,
            f"{-reference['width'] - gap}x{-reference['height'] - gap}",
        )

    def test_the_lowest_corner_of_the_layout_is_measured_from(self) -> None:
        # The two axes are minimised independently: no single monitor sits at
        # the corner the stage is measured from.
        corner = self.place(
            [
                {"name": "DP-1", "x": 0, "y": 0},
                {"name": "HDMI-A-1", "x": -1920, "y": 600},
                {"name": "DP-2", "x": 2560, "y": -300},
            ]
        )
        gap = stage_module.STAGE_GAP
        self.assertEqual(corner, (-1920 - 2560 - gap, -300 - 1440 - gap))


class StageWatchDecisionTests(unittest.TestCase):
    """The watcher's per-event decision, with every collaborator injected.

    The CLI-level fake drives the full loop elsewhere; these pin the decision
    itself: a window is moved only on positive ownership, and the address the
    dispatch names carries the 0x prefix socket2 leaves off.
    """

    SESSION = "feeba2a005d6558bfffb8c35"
    WORKSPACE = "svwsfeeba2a0"

    def decide(
        self,
        line: str,
        resolve=lambda address: 4242,
        marker=lambda pid, session: True,
        roots=lambda: [],
        descendants=lambda root: set(),
    ) -> str | None:
        return watch_module.event_dispatch(
            line, self.SESSION, self.WORKSPACE, resolve, marker, roots, descendants
        )

    def test_an_owned_window_off_the_stage_is_moved(self) -> None:
        self.assertEqual(
            self.decide("openwindow>>5601ab,4,imgpreview_x,preview"),
            f"name:{self.WORKSPACE},address:0x5601ab",
        )

    def test_an_unowned_window_is_left_alone(self) -> None:
        self.assertIsNone(
            self.decide(
                "openwindow>>5601ab,4,App,Doc",
                marker=lambda pid, session: False,
            )
        )

    def test_a_descendant_is_owned_without_the_marker(self) -> None:
        # A staged child that scrubbed its environment is still caught through
        # the recorded spawn's pid tree.
        self.assertEqual(
            self.decide(
                "openwindow>>5601ab,4,App,Doc",
                marker=lambda pid, session: False,
                roots=lambda: [10],
                descendants=lambda root: {10, 4242},
            ),
            f"name:{self.WORKSPACE},address:0x5601ab",
        )

    def test_a_window_already_on_the_stage_is_not_even_resolved(self) -> None:
        def resolve(address: str) -> int:
            raise AssertionError("a window on the stage was looked up")

        self.assertIsNone(
            self.decide(
                f"openwindow>>5601ab,{self.WORKSPACE},imgpreview_x,preview",
                resolve=resolve,
            )
        )

    def test_an_unresolvable_window_is_never_moved(self) -> None:
        # "the clients query failed" and "nothing owns it" both read as an
        # address without a pid, and neither may justify a move.
        self.assertIsNone(
            self.decide("openwindow>>5601ab,4,App,Doc", resolve=lambda address: None)
        )

    def test_other_events_and_malformed_lines_are_ignored(self) -> None:
        for line in [
            "closewindow>>5601ab",
            "workspacev2>>4,4",
            "openwindow>>5601ab",
            "openwindow",
            "",
        ]:
            self.assertIsNone(self.decide(line), line)

    def test_commas_in_the_title_never_shift_the_workspace_field(self) -> None:
        self.assertEqual(
            self.decide("openwindow>>5601ab,4,App,a title, with, commas"),
            f"name:{self.WORKSPACE},address:0x5601ab",
        )


if __name__ == "__main__":
    unittest.main()
