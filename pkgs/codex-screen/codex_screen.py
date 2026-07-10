#!/usr/bin/env python3
"""Audited, notifying screen capture sessions for cooperative Codex use."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import signal
import stat
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


SESSION_TTL_SECONDS = 24 * 60 * 60
AUDIT_TTL_DAYS = 90
AUDIT_MAX_BYTES = 1024 * 1024


class ScreenError(RuntimeError):
    pass


def now() -> datetime:
    return datetime.now(timezone.utc)


def runtime_root() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR")
    if not base:
        base = f"/run/user/{os.getuid()}"
    return Path(base) / "codex-screen"


def state_root() -> Path:
    base = os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))
    return Path(base) / "codex-screen"


def private_dir(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.chmod(0o700)


def atomic_json(path: Path, value: Any) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError) as error:
        raise ScreenError(f"Invalid or missing session: {path.parent.name}") from error


def run_json(command: list[str]) -> Any:
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
        return json.loads(result.stdout)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        raise ScreenError(f"Command failed: {command[0]}") from error


def notify(summary: str, body: str) -> None:
    try:
        subprocess.run(
            ["notify-send", "--app-name=Codex screen", summary, body],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def current_mode() -> str:
    try:
        result = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
            check=True,
            capture_output=True,
            text=True,
        )
        return "light" if "light" in result.stdout else "dark"
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def audit(
    event: str,
    *,
    session: str,
    target: str | None = None,
    monitor: str | None = None,
    outcome: str = "ok",
) -> None:
    root = state_root()
    private_dir(root)
    path = root / "audit.jsonl"
    rotate_audit(path)
    entry = {
        "time": now().isoformat(),
        "session": session,
        "event": event,
        "outcome": outcome,
    }
    if target is not None:
        entry["target"] = target
    if monitor is not None:
        entry["monitor"] = monitor
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, separators=(",", ":")) + "\n")
    path.chmod(0o600)


def rotate_audit(path: Path) -> None:
    if not path.exists():
        return
    cutoff = now() - timedelta(days=AUDIT_TTL_DAYS)
    retained: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            entry = json.loads(line)
            timestamp = datetime.fromisoformat(entry["time"])
        except (json.JSONDecodeError, KeyError, ValueError):
            continue
        if timestamp >= cutoff:
            retained.append(json.dumps(entry, separators=(",", ":")))
    encoded = "\n".join(retained)
    if encoded:
        encoded += "\n"
    while len(encoded.encode()) > AUDIT_MAX_BYTES and retained:
        retained.pop(0)
        encoded = "\n".join(retained)
        if encoded:
            encoded += "\n"
    path.write_text(encoded, encoding="utf-8")
    path.chmod(0o600)


def purge_abandoned() -> None:
    root = runtime_root()
    private_dir(root)
    cutoff = time.time() - SESSION_TTL_SECONDS
    for child in root.iterdir():
        if not child.is_dir() or child.is_symlink():
            continue
        if child.stat().st_mtime >= cutoff:
            continue
        session = child.name
        terminate_owned_processes(child)
        shutil.rmtree(child)
        audit("purge", session=session)


def session_dir(session: str) -> Path:
    if not session or any(character not in "abcdefghijklmnopqrstuvwxyz0123456789-" for character in session):
        raise ScreenError("Invalid session identifier")
    path = runtime_root() / session
    if not path.is_dir() or path.is_symlink():
        raise ScreenError(f"Invalid or missing session: {session}")
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        raise ScreenError("Session directory is not private")
    return path


def command_begin(_: argparse.Namespace) -> dict[str, Any]:
    purge_abandoned()
    session = f"{int(time.time())}-{secrets.token_hex(6)}"
    path = runtime_root() / session
    private_dir(path)
    data = {
        "session": session,
        "started_at": now().isoformat(),
        "mode": current_mode(),
        "captures": 0,
        "processes": [],
    }
    atomic_json(path / "session.json", data)
    audit("begin", session=session)
    return {"session": session, "mode": data["mode"]}


def focused_monitor() -> str:
    workspace = run_json(["hyprctl", "activeworkspace", "-j"])
    monitor = workspace.get("monitor")
    if not isinstance(monitor, str) or not monitor:
        raise ScreenError("Hyprland did not report a focused monitor")
    return monitor


def active_window_geometry() -> str:
    window = run_json(["hyprctl", "activewindow", "-j"])
    position = window.get("at")
    size = window.get("size")
    if not (
        isinstance(position, list)
        and isinstance(size, list)
        and len(position) == 2
        and len(size) == 2
        and all(isinstance(value, int) for value in position + size)
    ):
        raise ScreenError("Hyprland did not report active-window geometry")
    return f"{position[0]},{position[1]} {size[0]}x{size[1]}"


def capture_command(
    args: argparse.Namespace, output: Path
) -> tuple[list[str], str, str | None]:
    target = args.target
    if target == "focused":
        monitor = focused_monitor()
        return ["grim", "-o", monitor, str(output)], target, monitor
    if target == "monitor":
        if not args.monitor:
            raise ScreenError("--monitor is required for target monitor")
        return ["grim", "-o", args.monitor, str(output)], target, args.monitor
    if target == "all":
        return ["grim", str(output)], target, None
    if target == "window":
        return ["grim", "-g", active_window_geometry(), str(output)], target, None
    if target == "region":
        geometry = args.geometry
        if not geometry:
            try:
                geometry = subprocess.run(
                    ["slurp"], check=True, capture_output=True, text=True
                ).stdout.strip()
            except (OSError, subprocess.CalledProcessError) as error:
                raise ScreenError("Region selection was cancelled") from error
        if not geometry:
            raise ScreenError("Region selection was empty")
        return ["grim", "-g", geometry, str(output)], target, None
    raise ScreenError(f"Unsupported capture target: {target}")


def command_capture(args: argparse.Namespace) -> dict[str, Any]:
    purge_abandoned()
    path = session_dir(args.session)
    data = read_json(path / "session.json")
    capture_number = int(data.get("captures", 0)) + 1
    output = path / f"capture-{capture_number:03d}.png"
    command, audit_target, audit_monitor = capture_command(args, output)
    try:
        subprocess.run(command, check=True)
        output.chmod(0o600)
    except (OSError, subprocess.CalledProcessError) as error:
        output.unlink(missing_ok=True)
        audit(
            "capture",
            session=args.session,
            target=audit_target,
            monitor=audit_monitor,
            outcome="failed",
        )
        raise ScreenError("Screen capture failed") from error
    data["captures"] = capture_number
    atomic_json(path / "session.json", data)
    audit(
        "capture",
        session=args.session,
        target=audit_target,
        monitor=audit_monitor,
    )
    notify("Screen captured", f"{audit_target} · session {args.session[-6:]}")
    return {"path": str(output), "target": audit_target, "mode": data["mode"]}


def process_start_time(pid: int) -> str:
    fields = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8").split()
    return fields[21]


def descendant_pids(parent: int) -> set[int]:
    descendants = {parent}
    changed = True
    while changed:
        changed = False
        for status in Path("/proc").glob("[0-9]*/status"):
            try:
                lines = status.read_text(encoding="utf-8").splitlines()
                pid = int(status.parent.name)
                ppid = int(
                    next(line for line in lines if line.startswith("PPid:")).split()[1]
                )
            except (FileNotFoundError, PermissionError, StopIteration, ValueError):
                continue
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return descendants


def associated_window(pid: int, wait_seconds: float) -> dict[str, Any] | None:
    deadline = time.monotonic() + wait_seconds
    while True:
        try:
            clients = run_json(["hyprctl", "clients", "-j"])
        except ScreenError:
            return None
        if isinstance(clients, list):
            owned_pids = descendant_pids(pid)
            for client in clients:
                if client.get("pid") in owned_pids:
                    return {
                        "address": client.get("address"),
                        "pid": client.get("pid"),
                    }
        if time.monotonic() >= deadline:
            return None
        time.sleep(0.1)


def command_launch(args: argparse.Namespace) -> dict[str, Any]:
    purge_abandoned()
    path = session_dir(args.session)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        raise ScreenError("A command is required after --")
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as error:
        audit("launch", session=args.session, outcome="failed")
        raise ScreenError("Application launch failed") from error
    owned_process = {
        "pid": process.pid,
        "start_time": process_start_time(process.pid),
        "keep_open": args.keep_open,
    }
    window = associated_window(process.pid, args.wait_seconds)
    if window:
        owned_process["window"] = window
    data = read_json(path / "session.json")
    data.setdefault("processes", []).append(owned_process)
    atomic_json(path / "session.json", data)
    audit("launch", session=args.session)
    return {
        "pid": process.pid,
        "owned": True,
        "keep_open": args.keep_open,
        "window": window,
    }


def command_adapter(args: argparse.Namespace) -> dict[str, Any]:
    adapters = {
        "alacritty": ["alacritty", "--class", "Codex-visual-alacritty"],
        "neovim": [
            "alacritty",
            "--class",
            "Codex-visual-neovim",
            "-e",
            "nvim",
        ],
        "btop": [
            "alacritty",
            "--class",
            "Codex-visual-btop",
            "-e",
            "btop",
        ],
        "rofi": ["rofi", "-show", "drun"],
    }
    if args.name == "desktop":
        mode_result = command_ensure_mode(argparse.Namespace(session=args.session))
        audit("adapter", session=args.session)
        return {"adapter": args.name, "owned": False, "mode": mode_result["mode"]}
    if args.name == "notification":
        notify("Visual verification", "Mako notification palette and typography")
        audit("adapter", session=args.session)
        return {"adapter": args.name, "owned": False}
    launch_args = argparse.Namespace(
        session=args.session,
        command=adapters[args.name],
        keep_open=args.keep_open,
        wait_seconds=args.wait_seconds,
    )
    result = command_launch(launch_args)
    result["adapter"] = args.name
    return result


def terminate_owned_processes(path: Path) -> int:
    try:
        data = read_json(path / "session.json")
    except ScreenError:
        return 0
    terminated = 0
    for process in data.get("processes", []):
        if process.get("keep_open"):
            continue
        pid = process.get("pid")
        start_time = process.get("start_time")
        if not isinstance(pid, int) or not isinstance(start_time, str):
            continue
        try:
            if process_start_time(pid) != start_time:
                continue
            os.killpg(pid, signal.SIGTERM)
            terminated += 1
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return terminated


def expected_mode() -> str:
    try:
        result = subprocess.run(
            ["darkman", "get"], check=True, capture_output=True, text=True
        )
        value = result.stdout.strip()
        return value if value in {"dark", "light"} else "unknown"
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def command_ensure_mode(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    data = read_json(path / "session.json")
    mode = data.get("mode")
    if mode not in {"dark", "light"}:
        raise ScreenError("The session starting mode is unknown")
    live_mode = current_mode()
    if live_mode != mode:
        if live_mode in {"dark", "light"}:
            data["restore_mode"] = live_mode
            atomic_json(path / "session.json", data)
        subprocess.run([f"switch-{mode}"], check=True)
    audit("ensure-mode", session=args.session)
    return {"mode": mode}


def command_end(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    data = read_json(path / "session.json")
    terminated = terminate_owned_processes(path)
    desired_mode = expected_mode()
    if desired_mode == "unknown":
        desired_mode = data.get("restore_mode", "unknown")
    if desired_mode in {"dark", "light"} and current_mode() != desired_mode:
        try:
            subprocess.run([f"switch-{desired_mode}"], check=True)
        except (OSError, subprocess.CalledProcessError):
            audit("restore-mode", session=args.session, outcome="failed")
    shutil.rmtree(path)
    audit("end", session=args.session)
    notify("Visual verification finished", f"Cleaned session {args.session[-6:]}")
    return {"cleaned": True, "terminated": terminated, "restored_mode": desired_mode}


def command_status(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    data = read_json(path / "session.json")
    return {
        "session": args.session,
        "mode": data.get("mode"),
        "captures": data.get("captures", 0),
        "processes": len(data.get("processes", [])),
    }


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="codex-screen")
    commands = root.add_subparsers(dest="subcommand", required=True)

    begin = commands.add_parser("begin", help="start an ephemeral verification session")
    begin.set_defaults(handler=command_begin)

    capture = commands.add_parser("capture", help="capture a display target")
    capture.add_argument("--session", required=True)
    capture.add_argument(
        "--target",
        choices=["focused", "monitor", "all", "window", "region"],
        default="focused",
    )
    capture.add_argument("--monitor")
    capture.add_argument("--geometry")
    capture.set_defaults(handler=command_capture)

    launch = commands.add_parser("launch", help="launch and own a test process")
    launch.add_argument("--session", required=True)
    launch.add_argument("--keep-open", action="store_true")
    launch.add_argument("--wait-seconds", type=float, default=5.0)
    launch.add_argument("command", nargs=argparse.REMAINDER)
    launch.set_defaults(handler=command_launch)

    adapter = commands.add_parser("adapter", help="launch a known visual test surface")
    adapter.add_argument("--session", required=True)
    adapter.add_argument("--keep-open", action="store_true")
    adapter.add_argument("--wait-seconds", type=float, default=5.0)
    adapter.add_argument(
        "name",
        choices=["desktop", "alacritty", "neovim", "btop", "rofi", "notification"],
    )
    adapter.set_defaults(handler=command_adapter)

    ensure_mode = commands.add_parser(
        "ensure-mode", help="return the desktop to the session starting mode"
    )
    ensure_mode.add_argument("--session", required=True)
    ensure_mode.set_defaults(handler=command_ensure_mode)

    end = commands.add_parser("end", help="clean captures and owned processes")
    end.add_argument("--session", required=True)
    end.set_defaults(handler=command_end)

    status = commands.add_parser("status", help="show non-sensitive session metadata")
    status.add_argument("--session", required=True)
    status.set_defaults(handler=command_status)
    return root


def main() -> int:
    try:
        arguments = parser().parse_args()
        result = arguments.handler(arguments)
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except (ScreenError, subprocess.CalledProcessError) as error:
        print(f"codex-screen: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
