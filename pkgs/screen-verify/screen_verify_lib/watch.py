"""A per-session listener that pulls escaped staged windows back to the stage.

Hyprland's exec workspace rule is one-shot: it is consumed by the first window
of the spawned tree, so a later child window (an image-preview overlay, a
dialog) maps on the user's focused workspace instead. There is no pid- or
tree-based window rule, and workspace rules only act at map time, so the only
tree-wide capture is this: read `openwindow` events off socket2 and move each
window the session can positively own back onto its staging workspace.
"""

from __future__ import annotations

import os
import socket
from pathlib import Path
from typing import Callable

from .desktop import descendant_pids, has_stage_marker, process_start_time
from .stage import (
    hyprctl_quiet,
    lookup_clients,
    move_window_silent_lua,
    stage_record,
    stage_workspace_name,
)
from .state import ScreenError, read_json


# How long a quiet socket may block before the exit conditions are rechecked,
# so a watcher whose session vanished without signalling it still leaves
# within about a second.
RECHECK_SECONDS = 1.0


def socket2_path() -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not runtime or not signature:
        raise ScreenError("Hyprland's event socket could not be located")
    return Path(runtime) / "hypr" / signature / ".socket2.sock"


def parse_openwindow(line: str) -> tuple[str, str] | None:
    """(address, workspace) from one socket2 line, or None for anything else.

    socket2 lines are `EVENT>>DATA`; openwindow data is
    `ADDRESS,WORKSPACENAME,CLASS,TITLE`. Only the first two fields are read,
    so a comma in a class or title cannot shift them. A comma in a workspace
    name would, but the only workspace ever compared against is the sv-derived
    stage name, which cannot hold one.
    """
    event, separator, payload = line.partition(">>")
    if not separator or event != "openwindow":
        return None
    fields = payload.split(",", 2)
    if len(fields) < 2:
        return None
    return fields[0], fields[1]


def window_pid(address: str) -> int | None:
    """The live pid behind a socket2 address, or None when nothing answers.

    socket2 emits the address as bare hex; `clients` reports it with a `0x`
    prefix, so the prefix is restored before matching.
    """
    live = lookup_clients()
    if live is None:
        return None
    for client in live:
        if client.get("address") == f"0x{address}":
            pid = client.get("pid")
            return pid if isinstance(pid, int) else None
    return None


def staged_root_pids(path: Path) -> list[int]:
    """The recorded staged spawn pids, read fresh from the session file.

    Launches happen while the watcher runs, so a cached set would miss every
    spawn after the first. The recorded start time is compared before a pid is
    trusted: a recycled pid would hand its unrelated descendants a claim on
    windows this session never owned.
    """
    try:
        data = read_json(path / "session.json")
    except ScreenError:
        return []
    pids = []
    for process in data.get("processes", []):
        if process.get("spawn") != "stage":
            continue
        pid = process.get("pid")
        start_time = process.get("start_time")
        if not isinstance(pid, int) or not isinstance(start_time, str):
            continue
        try:
            if process_start_time(pid) != start_time:
                continue
        except OSError:
            continue
        pids.append(pid)
    return pids


def event_dispatch(
    line: str,
    session: str,
    workspace: str,
    resolve_pid: Callable[[str], int | None],
    marker: Callable[[int, str], bool],
    roots: Callable[[], list[int]],
    descendants: Callable[[int], set[int]],
) -> str | None:
    """The `hyprctl dispatch` argument one event line calls for, or None.

    Every collaborator is injected so the decision is testable without a
    socket or a compositor. A window is only ever moved on positive ownership:
    a line that is not an openwindow event, a window already on the stage, an
    address no clients query can resolve, and a pid that neither carries the
    session marker nor descends from a recorded staged spawn all decide
    "leave it" — the watcher must never touch a window it does not own.
    """
    parsed = parse_openwindow(line)
    if parsed is None:
        return None
    address, placed = parsed
    if placed == workspace:
        return None
    pid = resolve_pid(address)
    if pid is None:
        return None
    if not marker(pid, session) and not any(
        pid in descendants(root) for root in roots()
    ):
        return None
    return move_window_silent_lua(f"name:{workspace}", f"0x{address}")


def session_watchable(path: Path, session: str) -> bool:
    """True while the session still holds a stage worth watching over."""
    try:
        data = read_json(path / "session.json")
        return stage_record(data, session) is not None
    except ScreenError:
        return False


def watch_stage(path: Path, session: str) -> None:
    """Read socket2 until the session's stage record disappears.

    Exits on its own on socket EOF, on a socket error, and — via the receive
    timeout — within about a second of the session directory or its stage
    record going away, so `end` failing to signal the watcher never strands
    one. Failed dispatches are ignored: the watcher degrades staging back to
    its old behaviour rather than ever failing the session.
    """
    workspace = stage_workspace_name(session)
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        connection.connect(str(socket2_path()))
    except OSError as error:
        raise ScreenError("Hyprland's event socket could not be opened") from error
    connection.settimeout(RECHECK_SECONDS)
    buffer = b""
    with connection:
        while session_watchable(path, session):
            try:
                chunk = connection.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                return
            if not chunk:
                return
            buffer += chunk
            while b"\n" in buffer:
                raw, _, buffer = buffer.partition(b"\n")
                target = event_dispatch(
                    raw.decode("utf-8", "replace"),
                    session,
                    workspace,
                    window_pid,
                    has_stage_marker,
                    lambda: staged_root_pids(path),
                    descendant_pids,
                )
                if target is not None:
                    hyprctl_quiet("dispatch", target)
