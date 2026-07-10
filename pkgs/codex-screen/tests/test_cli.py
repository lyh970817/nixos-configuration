from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "codex_screen.py"


class CodexScreenCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.runtime = self.root / "runtime"
        self.state = self.root / "state"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "commands.jsonl"
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "HOME": str(self.root / "home"),
                "XDG_RUNTIME_DIR": str(self.runtime),
                "XDG_STATE_HOME": str(self.state),
                "PATH": f"{self.bin}:{os.environ['PATH']}",
                "FAKE_COMMAND_LOG": str(self.log),
            }
        )
        self.fake(
            "hyprctl",
            """#!/bin/sh
if [ "$1" = activeworkspace ]; then printf '%s\n' '{"monitor":"DP-1"}'; else printf '%s\n' '{"at":[10,20],"size":[800,600]}'; fi
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
        self.temporary.cleanup()

    def fake(self, name: str, contents: str) -> None:
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o755)

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

        audit = (self.state / "codex-screen/audit.jsonl").read_text()
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
            "--wait-seconds",
            "0",
            "--",
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
        )

        result = self.cli("end", "--session", session)

        self.assertTrue(result["cleaned"])
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
        old_path = self.runtime / "codex-screen" / old_session
        old_time = time.time() - 25 * 60 * 60
        os.utime(old_path, (old_time, old_time))

        self.begin()

        self.assertFalse(old_path.exists())
        audit = (self.state / "codex-screen/audit.jsonl").read_text()
        self.assertIn('"event":"purge"', audit)

    def test_audit_rotation_drops_entries_older_than_90_days(self) -> None:
        audit_dir = self.state / "codex-screen"
        audit_dir.mkdir(parents=True)
        audit_path = audit_dir / "audit.jsonl"
        audit_path.write_text(
            '{"time":"2020-01-01T00:00:00+00:00","session":"old","event":"begin","outcome":"ok"}\n'
        )

        self.begin()

        self.assertNotIn('"session":"old"', audit_path.read_text())

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
            "--wait-seconds",
            "1",
            "--",
            str(helper),
        )
        try:
            self.assertEqual(result["window"]["address"], "0xabc")
            audit = (self.state / "codex-screen/audit.jsonl").read_text()
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
        target = self.root / "home/.config/alacritty/current.toml"
        original = self.root / "original.toml"
        preview = self.root / "preview.toml"
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
if [ "$1" = getoption ]; then printf '%s\\n' '{{"custom":"4"}}'; elif [ "$1" = keyword ]; then printf 'hyprctl %s\\n' "$*" >> {actions}; else printf '%s\\n' '{{"monitor":"DP-1"}}'; fi
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
        self.assertIn("hyprctl keyword general:gaps_in 20", action_lines)
        self.assertIn("hyprctl keyword general:gaps_in 4", action_lines)
        self.assertIn("makoctl mode -s dark", action_lines)
        self.assertIn("makoctl mode -s default", action_lines)

    def test_every_command_purges_abandoned_sessions(self) -> None:
        old_session = self.begin()
        old_path = self.runtime / "codex-screen" / old_session
        old_time = time.time() - 25 * 60 * 60
        os.utime(old_path, (old_time, old_time))

        self.cli("status", "--session", old_session, check=False)

        self.assertFalse(old_path.exists())


if __name__ == "__main__":
    unittest.main()
