#!/usr/bin/env python3
"""Audited, notifying screen capture sessions for cooperative agent use."""

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

from screen_verify_lib.desktop import (
    ADAPTER_COMMANDS,
    ADAPTER_NAMES,
    active_window_geometry,
    associated_window,
    current_mode,
    descendant_pids,
    expected_mode,
    focused_monitor,
    notify,
    process_start_time,
    window_geometry,
)
from screen_verify_lib.preview import (
    command_preview_gsettings,
    command_preview_hypr_keyword,
    command_preview_mako_mode,
    command_preview_symlink,
    restore_previews,
)
from screen_verify_lib.stage import (
    POLL_SECONDS,
    client_workspace,
    ensure_stage,
    ensure_stage_workspace,
    monitor_presence,
    owned_stage_addresses,
    release_stage_windows,
    remove_stage,
    remove_stage_output,
    staged_windows,
    stage_output_name,
    stage_record,
    stage_spawn,
    stop_watcher,
    sweep_stage_windows,
)
from screen_verify_lib.state import (
    ScreenError,
    atomic_json,
    audit,
    now,
    private_dir,
    read_json,
    runtime_root,
    session_dir,
)
from screen_verify_lib.watch import watch_stage


SESSION_TTL_SECONDS = 24 * 60 * 60
# SIGTERM is asynchronous, so without a short wait the staging output would be
# removed out from under windows that are still closing. Cleanup must never
# hang on a process that ignores the signal, so this is a hard bound.
TERMINATION_TIMEOUT_SECONDS = 0.5


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
        # An output name only ever derives from the session identifier, and
        # every session of ours is named by `secrets.token_hex`. A directory
        # that cannot be named after a session of ours is neither ours to
        # reclaim an output for nor ours to delete — whatever it holds, and
        # whether or not that happens to parse as a session file.
        if not all(character in "0123456789abcdef" for character in session):
            audit("purge", session=session, outcome="skipped")
            continue
        terminate_owned_processes(child)
        # The output is reclaimed first, and unrecorded as it goes, so a
        # session that cannot be cleaned up for any other reason still never
        # leaves a phantom monitor behind for every later purge to retry.
        try:
            read_json(child / "session.json")
        except ScreenError:
            # Nothing is restorable from an unreadable session, but the derived
            # output name still is, so it is reclaimed before the directory goes.
            remove_stage_output(stage_output_name(session))
            shutil.rmtree(child)
            audit("purge", session=session, outcome="unreadable")
            continue
        remove_stage(child)
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


def owned_window_geometry(data: dict[str, Any], stage: dict[str, Any]) -> str | None:
    """Geometry of the newest still-open window this session put on the stage.

    `grim -g` captures a region, not a window, so a client that only looks
    owned resolves to whatever happens to be stacked at those coordinates —
    the user's own screen. Ownership is therefore decided by the same filter
    `release_stage_windows` uses. Unlike that one, `keep_open` is irrelevant
    here: a staged window that `end` will close is still capturable.
    """
    owned = owned_stage_addresses(data, keep_open_only=False)
    if not owned:
        return None
    # An unanswerable clients query owns nothing here: with no live client to
    # read geometry from, capture refuses rather than aiming `grim -g` at
    # coordinates nobody confirmed.
    matched = staged_windows(owned, stage["workspace"]) or {}
    for process in reversed(data.get("processes", [])):
        window = process.get("window")
        if not isinstance(window, dict):
            continue
        client = matched.get(window.get("address"))
        geometry = window_geometry(client) if client is not None else None
        if geometry is not None:
            return geometry
    return None


def capture_command(
    args: argparse.Namespace, output: Path, data: dict[str, Any]
) -> tuple[list[str], str, str | None]:
    stage = stage_record(data, args.session)
    target = args.target
    presence = None
    if stage is not None and target in {None, "stage"}:
        presence = monitor_presence(stage["output"])
        if presence == "unknown":
            # Only a confirmed-absent output may soften the default target
            # below. Degrading on a query that merely failed would write the
            # user's own monitor into a session capture, which is exactly what
            # the stage exists to prevent.
            raise ScreenError("Hyprland could not be asked about the staging output")
    if target is None:
        # A recorded stage whose output never appeared, or has since gone, must
        # not turn the default capture into a hard failure; desktop
        # verification still has to work. An explicit request still fails.
        target = "stage" if presence == "present" else "focused"
    if target == "stage":
        if not stage:
            raise ScreenError("This session has no staging output")
        if presence != "present":
            raise ScreenError("The staging output is no longer present")
        ensure_stage_workspace(stage["output"], stage["workspace"])
        return ["grim", "-o", stage["output"], str(output)], target, stage["output"]
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
        # Under a stage the active window is the user's own. Falling back to it
        # would write the user's private screen into the session, so once a
        # stage exists the only capturable window is one this session launched
        # — whether none was ever recorded or they have all since closed.
        if stage:
            geometry = owned_window_geometry(data, stage)
            if geometry is None:
                raise ScreenError(
                    "No window launched by this session is still open on the stage"
                )
            return ["grim", "-g", geometry, str(output)], target, None
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
    command, audit_target, audit_monitor = capture_command(args, output, data)
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


def direct_spawn(command: list[str], session: str) -> int:
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError as error:
        audit("launch", session=session, outcome="failed")
        raise ScreenError("Application launch failed") from error
    return process.pid


def command_launch(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        raise ScreenError("A command is required after --")
    stage = None if args.no_stage else ensure_stage(path, args.session)
    if stage:
        pid = stage_spawn(path, args.session, command)
        spawn = "stage"
    else:
        pid = direct_spawn(command, args.session)
        spawn = "direct"
    try:
        start_time = process_start_time(pid)
    except OSError as error:
        audit("launch", session=args.session, outcome="failed")
        raise ScreenError("The launched process exited before it was owned") from error
    owned_process = {
        "pid": pid,
        "start_time": start_time,
        "keep_open": args.keep_open,
        "spawn": spawn,
    }
    window = associated_window(pid, args.wait_seconds)
    if window:
        owned_process["window"] = window
    data = read_json(path / "session.json")
    data.setdefault("processes", []).append(owned_process)
    atomic_json(path / "session.json", data)
    audit("launch", session=args.session)
    if stage:
        # Windows that mapped before the watcher could act are recovered here,
        # and the warning below then describes what the sweep could not fix
        # rather than what it never tried to.
        sweep_stage_windows(args.session, pid, stage["workspace"])
    result = {
        "pid": pid,
        "owned": True,
        "keep_open": args.keep_open,
        "window": window,
        "spawn": spawn,
        "stage": stage["output"] if stage else None,
    }
    if stage and window:
        placed = client_workspace(window["address"])
        if placed is not None and placed != stage["workspace"]:
            result["warning"] = (
                "The window did not land on the staging workspace; "
                "it is visible on the desktop"
            )
    return result


def command_adapter(args: argparse.Namespace) -> dict[str, Any]:
    if args.name == "desktop":
        mode_result = command_ensure_mode(argparse.Namespace(session=args.session))
        audit("adapter", session=args.session)
        return {"adapter": args.name, "owned": False, "mode": mode_result["mode"]}
    if args.name == "notification":
        notify("Visual verification", "Mako notification palette and typography")
        audit("adapter", session=args.session)
        return {"adapter": args.name, "owned": False}
    adapter = ADAPTER_COMMANDS[args.name]
    command = list(adapter["command"])
    no_stage = args.no_stage
    extra: dict[str, Any] = {}
    if adapter.get("surface") == "layer":
        # Workspace rules never match a layer surface, so the surface is aimed
        # at the staging output directly and spawned without the stage rule.
        if not no_stage:
            stage = ensure_stage(session_dir(args.session), args.session)
            command += [adapter["monitor_flag"], stage["output"]]
        no_stage = True
        if adapter.get("warning"):
            extra["warning"] = adapter["warning"]
    launch_args = argparse.Namespace(
        session=args.session,
        command=command,
        keep_open=args.keep_open,
        wait_seconds=args.wait_seconds,
        no_stage=no_stage,
    )
    result = command_launch(launch_args)
    result["adapter"] = args.name
    result.update(extra)
    return result


def command_stage_watch(args: argparse.Namespace) -> dict[str, Any]:
    # Internal: the detached per-session helper `ensure_stage` spawns. It runs
    # until the session's stage record disappears or socket2 closes, moving
    # escaped staged windows back onto the staging workspace as they open.
    path = session_dir(args.session)
    watch_stage(path, args.session)
    return {"watching": False}


def command_stage(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    stage = ensure_stage(path, args.session)
    return {
        "stage": True,
        "output": stage["output"],
        "workspace": stage["workspace"],
    }


def terminate_owned_processes(path: Path) -> list[int]:
    """SIGTERM every process this session owns; returns the signalled pids."""
    try:
        data = read_json(path / "session.json")
    except ScreenError:
        return []
    terminated = []
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
            if process.get("spawn") == "stage":
                # Hyprland spawned it, so it shares the compositor's process
                # group; only the tracked pid and its children may be signalled.
                terminate_tree(pid)
            else:
                os.killpg(pid, signal.SIGTERM)
            terminated.append(pid)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
    return terminated


def terminate_tree(pid: int) -> None:
    for target in sorted(descendant_pids(pid), reverse=True):
        try:
            os.kill(target, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            continue


def has_exited(pid: int) -> bool:
    """True once a pid is gone, or is a zombie its parent has yet to reap."""
    try:
        raw = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    except OSError:
        return True
    return raw.rsplit(")", 1)[1].split()[0] == "Z"


def wait_for_exit(pids: list[int]) -> None:
    """Wait, briefly, for terminated windows to leave before the stage does."""
    # Nothing terminated means nothing to wait for, so keep-open sessions and
    # sessions that launched nothing never pay for this at all.
    if not pids:
        return
    deadline = time.monotonic() + TERMINATION_TIMEOUT_SECONDS
    while not all(has_exited(pid) for pid in pids):
        if time.monotonic() >= deadline:
            return
        time.sleep(POLL_SECONDS)


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
    wait_for_exit(terminated)
    # The watcher goes before the stage does: it would exit on its own once
    # the record disappears, but only after its next recheck, and a watcher
    # racing the teardown could move a window `end` is about to hand back.
    stop_watcher(path)
    # The stage is reclaimed before anything that can fail, exactly as `purge`
    # does it: a preview that refuses to restore must not leave a phantom
    # headless monitor on the user's compositor for the rest of the day.
    # Windows the caller asked to keep outlive the stage, so they are handed
    # back to the user's own workspace before the output disappears.
    released, stranded = release_stage_windows(path)
    stage_removed = remove_stage(path)
    # A failed restore still retains the session directory and still fails the
    # command, so the user can retry it once the cause is fixed.
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
    result = {
        "cleaned": True,
        "terminated": len(terminated),
        "restored_previews": restored_previews,
        "restored_mode": desired_mode,
        "stage_removed": stage_removed,
    }
    if stranded:
        result["warning"] = (
            f"{stranded} kept window(s) could not be moved off the staging "
            "output before it was removed"
        )
    elif released:
        result["warning"] = (
            f"{released} kept window(s) were moved off the staging output "
            "onto the active workspace"
        )
    return result


def command_status(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    data = read_json(path / "session.json")
    stage = stage_record(data, args.session)
    return {
        "session": args.session,
        "mode": data.get("mode"),
        "captures": data.get("captures", 0),
        "processes": len(data.get("processes", [])),
        "stage": bool(stage),
        "stage_output": stage["output"] if stage else None,
    }


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="screen-verify")
    commands = root.add_subparsers(dest="subcommand", required=True)

    begin = commands.add_parser("begin", help="start an ephemeral verification session")
    begin.set_defaults(handler=command_begin)

    capture = commands.add_parser("capture", help="capture a display target")
    capture.add_argument("--session", required=True)
    capture.add_argument(
        "--target",
        choices=["focused", "monitor", "all", "window", "region", "stage"],
        default=None,
        help="default: stage when the session has one, otherwise focused",
    )
    capture.add_argument("--monitor")
    capture.add_argument("--geometry")
    capture.set_defaults(handler=command_capture)

    launch = commands.add_parser("launch", help="launch and own a test process")
    launch.add_argument("--session", required=True)
    launch.add_argument("--keep-open", action="store_true")
    launch.add_argument("--wait-seconds", type=float, default=5.0)
    launch.add_argument(
        "--no-stage",
        action="store_true",
        help="spawn on the current workspace instead of the staging output",
    )
    launch.add_argument("command", nargs=argparse.REMAINDER)
    launch.set_defaults(handler=command_launch)

    adapter = commands.add_parser("adapter", help="launch a known visual test surface")
    adapter.add_argument("--session", required=True)
    adapter.add_argument("--keep-open", action="store_true")
    adapter.add_argument("--wait-seconds", type=float, default=5.0)
    adapter.add_argument(
        "--no-stage",
        action="store_true",
        help="spawn on the current workspace instead of the staging output",
    )
    adapter.add_argument("name", choices=ADAPTER_NAMES)
    adapter.set_defaults(handler=command_adapter)

    stage = commands.add_parser(
        "stage", help="create the hidden headless output used for test windows"
    )
    stage.add_argument("--session", required=True)
    stage.set_defaults(handler=command_stage)

    # No help text: this is the internal watcher process, not a user command.
    stage_watch = commands.add_parser("stage-watch")
    stage_watch.add_argument("--session", required=True)
    stage_watch.set_defaults(handler=command_stage_watch)

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
        # The watcher is a long-lived background helper, not a user command;
        # purging from it would race the very sessions it exists to watch.
        if arguments.subcommand != "stage-watch":
            purge_abandoned()
        result = arguments.handler(arguments)
        print(json.dumps(result, separators=(",", ":")))
        return 0
    except (ScreenError, subprocess.CalledProcessError) as error:
        print(f"screen-verify: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
