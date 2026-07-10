#!/usr/bin/env python3
"""Audited, notifying screen capture sessions for cooperative Codex use."""

from __future__ import annotations

import argparse
import json
import os
import secrets
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from codex_screen_lib.desktop import (
    ADAPTER_COMMANDS,
    ADAPTER_NAMES,
    active_window_geometry,
    associated_window,
    current_mode,
    expected_mode,
    focused_monitor,
    notify,
    run_json,
)
from codex_screen_lib.preview import (
    command_preview_gsettings,
    command_preview_hypr_keyword,
    command_preview_mako_mode,
    command_preview_symlink,
    restore_previews,
)
from codex_screen_lib.state import (
    ScreenError,
    atomic_json,
    audit,
    now,
    private_dir,
    read_json,
    runtime_root,
    session_dir,
)


SESSION_TTL_SECONDS = 24 * 60 * 60


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
        try:
            restore_previews(child)
        except ScreenError:
            audit("purge", session=session, outcome="restore-failed")
            continue
        shutil.rmtree(child)
        audit("purge", session=session)


def command_begin(_: argparse.Namespace) -> dict[str, Any]:
    session = secrets.token_hex(12)
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


def command_launch(args: argparse.Namespace) -> dict[str, Any]:
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
        command=ADAPTER_COMMANDS[args.name],
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
    restored_previews = restore_previews(path)
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
    return {
        "cleaned": True,
        "terminated": terminated,
        "restored_previews": restored_previews,
        "restored_mode": desired_mode,
    }


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
    adapter.add_argument("name", choices=ADAPTER_NAMES)
    adapter.set_defaults(handler=command_adapter)

    preview = commands.add_parser(
        "preview", help="apply a session-managed reversible visual preview"
    )
    preview_kinds = preview.add_subparsers(dest="preview_kind", required=True)

    preview_symlink = preview_kinds.add_parser(
        "symlink", help="temporarily point a theme/config symlink at a source"
    )
    preview_symlink.add_argument("--session", required=True)
    preview_symlink.add_argument("--target", required=True)
    preview_symlink.add_argument("--source", required=True)
    preview_symlink.set_defaults(handler=command_preview_symlink)

    preview_gsettings = preview_kinds.add_parser(
        "gsettings", help="temporarily set a GTK/GSettings value"
    )
    preview_gsettings.add_argument("--session", required=True)
    preview_gsettings.add_argument("--schema", required=True)
    preview_gsettings.add_argument("--key", required=True)
    preview_gsettings.add_argument("--value", required=True)
    preview_gsettings.set_defaults(handler=command_preview_gsettings)

    preview_hypr = preview_kinds.add_parser(
        "hypr-keyword", help="temporarily set a Hyprland runtime keyword"
    )
    preview_hypr.add_argument("--session", required=True)
    preview_hypr.add_argument("--keyword", required=True)
    preview_hypr.add_argument("--value", required=True)
    preview_hypr.set_defaults(handler=command_preview_hypr_keyword)

    preview_mako = preview_kinds.add_parser(
        "mako-mode", help="temporarily replace the active Mako modes"
    )
    preview_mako.add_argument("--session", required=True)
    preview_mako.add_argument("--mode", required=True)
    preview_mako.set_defaults(handler=command_preview_mako_mode)

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
        purge_abandoned()
        result = arguments.handler(arguments)
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except (ScreenError, subprocess.CalledProcessError) as error:
        print(f"codex-screen: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
