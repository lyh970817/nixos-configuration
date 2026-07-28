"""A headless Hyprland output that hosts test windows off the user's screen."""

from __future__ import annotations

import os
import secrets
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from .desktop import (
    STAGE_MARKER,
    descendant_pids,
    has_stage_marker,
    process_start_time,
    run_json,
)
from .state import ScreenError, atomic_json, audit, read_json


# Both stage polls use this budget in turn, so a wedged compositor delays
# `ensure_stage` by at most twice it — roughly six seconds worst case.
STAGE_TIMEOUT_SECONDS = 3.0
PID_TIMEOUT_SECONDS = 5.0
POLL_SECONDS = 0.1
# Empty space kept between the stage and the nearest real monitor, on both
# axes. Any positive gap is enough to make the stage unreachable; this one is
# wide enough that a monitor appearing at a slightly different origin than the
# one we read cannot close it.
STAGE_GAP = 2000
FALLBACK_MONITOR = {"width": 1920, "height": 1080, "scale": 1.0}
# The CLI entry point, reachable from both layouts this package runs in: the
# source checkout and the installed libexec tree both keep screen_verify.py one
# directory above this module.
CLI_SCRIPT = Path(__file__).resolve().parent.parent / "screen_verify.py"


def stage_output_name(session: str) -> str:
    return f"svstage{session[:8]}"


def stage_workspace_name(session: str) -> str:
    return f"svws{session[:8]}"


def hyprctl(*arguments: str) -> None:
    try:
        subprocess.run(
            ["hyprctl", *arguments],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        message = " ".join(arguments)
        raise ScreenError(f"Hyprland rejected: hyprctl {message}") from error


def hyprctl_quiet(*arguments: str) -> None:
    try:
        subprocess.run(
            ["hyprctl", *arguments],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def monitors() -> list[dict[str, Any]]:
    data = run_json(["hyprctl", "monitors", "-j"])
    if not isinstance(data, list):
        return []
    return [entry for entry in data if isinstance(entry, dict)]


def lookup_monitor(name: str) -> tuple[str, dict[str, Any] | None]:
    """("present" | "absent" | "unknown", entry) for a named output.

    A failed query is not evidence that an output is gone. Any decision that
    would expose the user's own screen — or claim a removal — has to tell the
    two apart; a polling loop legitimately does not.
    """
    if not name:
        return "absent", None
    try:
        entries = monitors()
    except ScreenError:
        return "unknown", None
    for entry in entries:
        if entry.get("name") == name:
            return "present", entry
    return "absent", None


def monitor_presence(name: str) -> str:
    return lookup_monitor(name)[0]


def find_monitor(name: str) -> dict[str, Any] | None:
    """Best effort: an unanswerable query reads the same as a missing output."""
    return lookup_monitor(name)[1]


def focused_monitor_name() -> str | None:
    try:
        entries = monitors()
    except ScreenError:
        return None
    for entry in entries:
        if entry.get("focused"):
            name = entry.get("name")
            if isinstance(name, str) and name:
                return name
    return None


def focus_snapshot(stage_output: str) -> dict[str, Any]:
    window = None
    try:
        active = run_json(["hyprctl", "activewindow", "-j"])
    except ScreenError:
        active = None
    if isinstance(active, dict):
        address = active.get("address")
        if isinstance(address, str) and address:
            window = address
    try:
        entries = monitors()
    except ScreenError:
        entries = []
    focused = None
    fallback = None
    for entry in entries:
        name = entry.get("name")
        # The stage output is never a place to hand focus back to, and on the
        # idempotent re-entry path it can already exist.
        if not (isinstance(name, str) and name) or name == stage_output:
            continue
        if entry.get("focused"):
            focused = name
            break
        if fallback is None:
            fallback = name
    # A snapshot without a monitor turns `restore_focus` into a silent no-op
    # and leaves the user typing at the invisible stage, so one query that
    # reports no focus at all falls back to any real monitor.
    return {"monitor": focused or fallback, "window": window}


def restore_focus(snapshot: Any) -> None:
    if not isinstance(snapshot, dict):
        return
    monitor = snapshot.get("monitor")
    if isinstance(monitor, str) and monitor:
        hyprctl_quiet("dispatch", "focusmonitor", monitor)
    window = snapshot.get("window")
    if isinstance(window, str) and window:
        hyprctl_quiet("dispatch", "focuswindow", f"address:{window}")


def placement_snapshot() -> list[dict[str, Any]]:
    """The single layout reading that both sizes and places the stage.

    Never raises: this decides where the user's pointer can go, so a layout
    that cannot be read still has to yield a position rather than a failure,
    and an empty snapshot is what puts both callers on their fallbacks.
    """
    try:
        return monitors()
    except Exception:
        # Deliberately wider than `ScreenError`: no reading of the layout is
        # worth failing a stage over, and every failure lands on the fallback.
        return []


def reference_monitor(entries: list[dict[str, Any]]) -> dict[str, Any]:
    for entry in entries:
        if entry.get("focused"):
            return monitor_geometry(entry)
    return dict(FALLBACK_MONITOR)


def monitor_geometry(entry: dict[str, Any]) -> dict[str, Any]:
    geometry = dict(FALLBACK_MONITOR)
    width = entry.get("width")
    height = entry.get("height")
    scale = entry.get("scale")
    if isinstance(width, int) and width > 0:
        geometry["width"] = width
    if isinstance(height, int) and height > 0:
        geometry["height"] = height
    if isinstance(scale, (int, float)) and float(scale) > 0:
        geometry["scale"] = float(scale)
    return geometry


def stage_position(entries: list[dict[str, Any]], width: int, height: int) -> str:
    """The `<x>x<y>` that parks a width x height stage clear of every monitor.

    Never raises, whatever the snapshot holds: this decides where the user's
    pointer can go, so a layout that could not be read still has to yield a
    position rather than a failure, and the origin is the safest thing to
    measure from when nothing answered.
    """
    corners = []
    for entry in entries:
        x = entry.get("x")
        y = entry.get("y")
        # A bool is an int in Python, and a monitor with only one axis placed
        # is no more usable than one with neither.
        if isinstance(x, bool) or isinstance(y, bool):
            continue
        if isinstance(x, int) and isinstance(y, int):
            corners.append((x, y))
    origin_x = min((x for x, _ in corners), default=0)
    origin_y = min((y for _, y in corners), default=0)
    return f"{origin_x - width - STAGE_GAP}x{origin_y - height - STAGE_GAP}"


def stage_info(data: Any) -> dict[str, Any] | None:
    stage = data.get("stage") if isinstance(data, dict) else None
    if stage is None:
        return None
    output = stage.get("output") if isinstance(stage, dict) else None
    workspace = stage.get("workspace") if isinstance(stage, dict) else None
    if not (isinstance(output, str) and output):
        raise ScreenError("The session holds an unusable stage record")
    if not (isinstance(workspace, str) and workspace):
        raise ScreenError("The session holds an unusable stage record")
    return stage


def stage_record(data: Any, session: str) -> dict[str, Any] | None:
    """The stage record, verified against the names derived from the session."""
    stage = stage_info(data)
    if stage is None:
        return None
    if stage["output"] != stage_output_name(session) or stage[
        "workspace"
    ] != stage_workspace_name(session):
        # Every reader derives the names it trusts; a record naming anything
        # else was not written by this session and must never steer hyprctl.
        raise ScreenError("The session holds a foreign stage record")
    return stage


def lookup_clients() -> list[dict[str, Any]] | None:
    """The live clients, or None when Hyprland could not be asked at all.

    Same discipline as `lookup_monitor`: a failed query is not evidence that a
    window is gone. Any decision that would let a window disappear with the
    staging output has to tell the two apart; a best-effort reader need not.
    """
    try:
        data = run_json(["hyprctl", "clients", "-j"])
    except ScreenError:
        return None
    if not isinstance(data, list):
        return []
    return [entry for entry in data if isinstance(entry, dict)]


def clients() -> list[dict[str, Any]]:
    """Best effort: an unanswerable query reads the same as no clients."""
    return lookup_clients() or []


def client_workspace(address: str) -> str | None:
    for client in clients():
        if client.get("address") != address:
            continue
        workspace = client.get("workspace")
        name = workspace.get("name") if isinstance(workspace, dict) else None
        return name if isinstance(name, str) and name else None
    return None


def wait_for_monitor(
    name: str, timeout: float = STAGE_TIMEOUT_SECONDS
) -> dict[str, Any] | None:
    deadline = time.monotonic() + timeout
    while True:
        monitor = find_monitor(name)
        if monitor is not None:
            return monitor
        if time.monotonic() >= deadline:
            return None
        time.sleep(POLL_SECONDS)


def wait_for_workspace(
    name: str, workspace: str, timeout: float = STAGE_TIMEOUT_SECONDS
) -> bool:
    deadline = time.monotonic() + timeout
    while True:
        monitor = find_monitor(name) or {}
        active = monitor.get("activeWorkspace")
        if isinstance(active, dict) and active.get("name") == workspace:
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(POLL_SECONDS)


def workspace_rule(output: str, workspace: str) -> str:
    return f"name:{workspace},monitor:{output},default:true"


def ensure_stage_workspace(output: str, workspace: str) -> None:
    """Fail unless the staging output is showing its own workspace right now.

    An output that adopted its workspace at creation can leave it later: the
    pointer walks onto it, a keybind or another tool dispatches a workspace, or
    a config reload drops the runtime rule. `grim -o` then succeeds against an
    empty workspace, so the blank capture has to be caught here instead.
    """
    if wait_for_workspace(output, workspace, 0):
        return
    # Both names derive from the session identifier, so nothing caller-supplied
    # is ever spliced into a hyprctl argument here.
    focus = focus_snapshot(output)
    hyprctl_quiet("keyword", "workspace", workspace_rule(output, workspace))
    hyprctl_quiet("dispatch", "moveworkspacetomonitor", f"name:{workspace} {output}")
    # Moving a workspace can carry focus with it, and the stage is never a
    # place to leave the user typing.
    restore_focus(focus)
    # Bounded to a few poll intervals: this is a repair, not a wait for a
    # compositor that is not going to answer.
    if not wait_for_workspace(output, workspace, POLL_SECONDS * 5):
        raise ScreenError(
            "The staging output is no longer showing its workspace; "
            "captures would have been blank"
        )


def watcher_alive(watcher: Any) -> bool:
    """True when the recorded watcher pid still names the recorded process."""
    if not isinstance(watcher, dict):
        return False
    pid = watcher.get("pid")
    start_time = watcher.get("start_time")
    if not isinstance(pid, int) or not isinstance(start_time, str):
        return False
    try:
        return process_start_time(pid) == start_time
    except OSError:
        return False


def start_watcher(path: Path, session: str) -> None:
    """Keep one detached socket2 watcher running for this session's stage.

    The workspace rule a staged spawn carries is one-shot: Hyprland consumes it
    when the first window of the tree maps, so any later child window maps on
    the user's focused workspace instead. The watcher is the only tree-wide
    net — it moves those windows back as they open — so it is started the
    moment the stage exists, before anything can be spawned onto it.

    Best effort throughout: a stage without its watcher still stages, exactly
    as it did before the watcher existed, and the launch-time sweep remains.
    """
    try:
        data = read_json(path / "session.json")
    except ScreenError:
        return
    stage = data.get("stage")
    if not isinstance(stage, dict):
        return
    # Check-then-spawn is not atomic, and sessions are driven by concurrent
    # CLI invocations: two of them can both find no live watcher and spawn one
    # each, with only one recorded. That race is benign — the duplicate makes
    # the same idempotent moves and leaves on its own once the stage record
    # disappears — so it is tolerated rather than locked against.
    if watcher_alive(stage.get("watcher")):
        return
    log = path / "watch.log"
    try:
        with log.open("ab") as handle:
            log.chmod(0o600)
            process = subprocess.Popen(
                [sys.executable, str(CLI_SCRIPT), "stage-watch", "--session", session],
                stdin=subprocess.DEVNULL,
                stdout=handle,
                stderr=handle,
                start_new_session=True,
            )
        # The pid alone would match a recycled process; the start time is what
        # `stop_watcher` compares before it may signal anything.
        stage["watcher"] = {
            "pid": process.pid,
            "start_time": process_start_time(process.pid),
        }
        # Inside the same net as the spawn: a session directory torn down
        # between the read above and this write must not fail the stage. The
        # watcher the record misses self-exits with the vanished session.
        atomic_json(path / "session.json", data)
    except OSError:
        return


def stop_watcher(path: Path) -> None:
    """SIGTERM this session's watcher, if the recorded pid is still it.

    The watcher also leaves on its own once the stage record disappears, so a
    watcher that is already dead — or whose pid now names another process —
    is simply left alone.
    """
    try:
        data = read_json(path / "session.json")
    except ScreenError:
        return
    stage = data.get("stage")
    watcher = stage.get("watcher") if isinstance(stage, dict) else None
    if not isinstance(watcher, dict):
        return
    pid = watcher.get("pid")
    start_time = watcher.get("start_time")
    if not isinstance(pid, int) or not isinstance(start_time, str):
        return
    try:
        if process_start_time(pid) != start_time:
            return
        os.kill(pid, signal.SIGTERM)
    except (OSError, ProcessLookupError, PermissionError):
        return


def ensure_stage(path: Path, session: str) -> dict[str, Any]:
    data = read_json(path / "session.json")
    existing = stage_record(data, session)
    output = stage_output_name(session)
    workspace = stage_workspace_name(session)
    if existing:
        presence = monitor_presence(output)
        if presence == "unknown":
            raise ScreenError("Hyprland could not be asked about the staging output")
        if presence == "present":
            # Existing is not enough: an output that has drifted off its
            # workspace would hand every later capture a blank image.
            ensure_stage_workspace(output, workspace)
            # A watcher that died with a crash or a logout is revived here, so
            # re-entry restores the same guarantees creation gives.
            start_watcher(path, session)
            return existing

    focus = focus_snapshot(output)
    # One reading of the layout answers both questions asked of it: how big the
    # stage should be, and where it may sit. Two queries can disagree, and a
    # second one that failed on a layout whose true origin is negative would
    # fall back to 0,0 and park the stage on top of a real monitor. The stage's
    # own output cannot appear in this snapshot -- it does not exist yet -- so
    # what is measured here is exactly the user's own screens.
    layout = placement_snapshot()
    reference = reference_monitor(layout)
    # Up and left of the whole layout, sharing an edge with nothing. A position
    # at or right of the real monitors makes Hyprland re-place the auto-placed
    # ones and shifts the coordinates of the user's own screen; `auto` itself
    # lands flush against its right edge. Adjacency is just as bad as overlap:
    # the pointer moves through one continuous space, so from a touching output
    # it walks off the real screen onto the invisible one and takes keyboard
    # focus with it under follow_mouse. A corner nothing touches cannot be
    # reached by a mouse at all.
    position = stage_position(layout, reference["width"], reference["height"])
    # Both rules must exist before the output does, because Hyprland applies a
    # rule by output name the moment an output of that name appears.
    #
    # A workspace rule installed afterwards leaves the output on a free numeric
    # workspace and every capture of the staging workspace silently comes back
    # blank. A monitor rule installed afterwards is worse: `output create`
    # takes no position, so Hyprland auto-places the new output flush against
    # the user's screen and it stays there until the rule lands -- a window of
    # a fraction of a second in which the pointer can walk onto the invisible
    # stage. Installed first, the output is placed correctly from birth.
    #
    # Neither rule can be removed at runtime, so two inert rules leak per
    # session; session-unique names keep that harmless.
    hyprctl("keyword", "workspace", workspace_rule(output, workspace))
    hyprctl(
        "keyword",
        "monitor",
        f"{output},{reference['width']}x{reference['height']}@60,"
        f"{position},{reference['scale']:g}",
    )
    # The record is persisted before the output exists so that a crash between
    # creating the output and finishing the stage still leaves `end` and
    # `purge` a stage to report and a focus snapshot to restore. Reclaiming the
    # output never depends on it: that name derives from the session alone.
    stage = {"output": output, "workspace": workspace, "focus": focus}
    data["stage"] = stage
    atomic_json(path / "session.json", data)
    try:
        hyprctl("output", "create", "headless", output)
        if wait_for_monitor(output) is None:
            raise ScreenError("Hyprland did not create the staging output")
        # Creating the output steals keyboard focus, so give it straight back.
        restore_focus(focus)
        if not wait_for_workspace(output, workspace):
            raise ScreenError(
                "The staging output did not adopt its workspace; "
                "captures would have been blank, so the output was removed"
            )
    except ScreenError:
        # Never leave a phantom monitor behind on a half-built stage.
        remove_stage_output(output)
        restore_focus(focus)
        data.pop("stage", None)
        atomic_json(path / "session.json", data)
        raise
    audit("stage", session=session, monitor=output)
    # Started only once the stage verifiably exists, and before `ensure_stage`
    # returns, so the watcher is listening before anything can be spawned.
    start_watcher(path, session)
    return stage


def remove_stage_output(name: str) -> None:
    if not name:
        return
    hyprctl_quiet("output", "remove", name)


def remove_stage(path: Path) -> bool:
    """Reclaim this session's output. True when a recorded stage is now gone."""
    try:
        data = read_json(path / "session.json")
    except ScreenError:
        return False
    try:
        stage = stage_info(data)
    except ScreenError:
        stage = None
    # The derived name is the only output this session can ever have created,
    # so it is reclaimed unconditionally: a record lost to a half-built stage
    # or an unwritable session file must still not strand a monitor. No other
    # name is ever removed, so no record can aim `output remove` elsewhere.
    recorded = "stage" in data
    name = stage_output_name(path.name)
    staged_focus = focused_monitor_name() == name
    remove_stage_output(name)
    if recorded and staged_focus:
        # Focus sat on the output that just vanished, so hand back the focus
        # the stage took. A stale snapshot is only trusted for that one case.
        restore_focus(stage.get("focus") if stage else None)
    if recorded:
        data.pop("stage", None)
        atomic_json(path / "session.json", data)
    if not recorded:
        # A session that never staged has nothing to report, and nothing to ask
        # the compositor about either.
        return False
    # `output remove` is fire-and-forget, so without this the result would
    # describe the record rather than the compositor. A query that cannot be
    # answered counts as "not removed": a removal must never be claimed on
    # anything weaker than the output being confirmed gone.
    return monitor_presence(name) == "absent"


def rescue_workspace(stage_output: str, focus: Any) -> str | None:
    try:
        entries = monitors()
    except ScreenError:
        return None
    candidates = [entry for entry in entries if entry.get("name") != stage_output]
    preferred = focus.get("monitor") if isinstance(focus, dict) else None
    chosen = None
    for entry in candidates:
        if entry.get("name") == preferred:
            chosen = entry
            break
    if chosen is None:
        chosen = next((entry for entry in candidates if entry.get("focused")), None)
    if chosen is None:
        chosen = candidates[0] if candidates else None
    active = chosen.get("activeWorkspace") if chosen else None
    identifier = active.get("id") if isinstance(active, dict) else None
    # Hyprland reads a leading "-" as a relative workspace shift, so the
    # negative id a special or named workspace reports would move the window
    # somewhere nobody asked for. Only an absolute id may be dispatched.
    if not isinstance(identifier, int) or identifier <= 0:
        return None
    return str(identifier)


def staged_windows(
    owned: dict[str, Any], workspace: str
) -> dict[str, dict[str, Any]] | None:
    """The live clients, by address, that really are this session's on the stage.

    None when the clients query could not be answered: "no window of ours is
    there" and "we could not find out" are different answers, and a caller that
    is about to remove the output must not read the second as the first.

    An address alone is never ownership: Hyprland addresses are object pointers
    and get reused, so the recorded pid must still match the live one. A client
    that reports another workspace never reached the stage and is already where
    the user wants it. An unreported workspace is evidence of neither, so
    ownership decides — a kept window is never left to vanish with the output.
    One `clients` query serves the whole answer.
    """
    live = lookup_clients()
    if live is None:
        return None
    matched: dict[str, dict[str, Any]] = {}
    for client in live:
        address = client.get("address")
        if address not in owned:
            continue
        placed = client.get("workspace")
        name = placed.get("name") if isinstance(placed, dict) else None
        if name is not None and name != workspace:
            continue
        pid = owned[address]
        if isinstance(pid, int) and client.get("pid") != pid:
            continue
        matched[address] = client
    return matched


def owned_stage_addresses(data: dict[str, Any], keep_open_only: bool) -> dict[str, Any]:
    """Recorded window address -> recorded pid, for windows spawned on the stage."""
    owned: dict[str, Any] = {}
    for process in data.get("processes", []):
        if process.get("spawn") != "stage":
            continue
        if keep_open_only and not process.get("keep_open"):
            continue
        window = process.get("window")
        if isinstance(window, dict) and isinstance(window.get("address"), str):
            owned[window["address"]] = window.get("pid")
    return owned


def release_stage_windows(path: Path) -> tuple[int, int]:
    """Move kept windows off the stage. Best effort; returns (moved, stranded)."""
    try:
        data = read_json(path / "session.json")
        stage = stage_record(data, path.name)
    except ScreenError:
        return 0, 0
    if stage is None:
        return 0, 0
    # Only windows the caller asked to keep outlive the stage; the rest are
    # terminated with the session.
    owned = owned_stage_addresses(data, keep_open_only=True)
    if not owned:
        return 0, 0
    matched = staged_windows(owned, stage["workspace"])
    if matched is None:
        # The output is removed either way, so an unanswerable query must not
        # be reported as "nothing to rescue": every kept window is counted
        # stranded so `end` warns instead of losing them without a word.
        return 0, len(owned)
    surviving = list(matched)
    if not surviving:
        return 0, 0
    workspace = rescue_workspace(stage["output"], stage.get("focus"))
    if workspace is None:
        return 0, len(surviving)
    for address in surviving:
        hyprctl_quiet(
            "dispatch",
            "movetoworkspacesilent",
            f"{workspace},address:{address}",
        )
    return len(surviving), 0


def stage_spawn(path: Path, session: str, command: list[str]) -> int:
    # The rule is built from the session identifier rather than from anything
    # read back out of session.json, so no stored value can ever escape the
    # rule block and become a second Hyprland dispatch.
    workspace = stage_workspace_name(session)
    pidfile = path / f"launch-{secrets.token_hex(4)}.pid"
    # Hyprland hands the whole exec string to /bin/sh, so every caller-supplied
    # argument is shell-quoted here: the shell never evaluates any of it. The
    # marker is exported before the exec so the whole tree inherits it — the
    # ownership test the watcher and the sweep rely on when a staged child
    # double-forks out of the pid tree. The trampoline records its own pid and
    # then execs in place, so the pid we own is the application itself.
    inner = (
        f"export {STAGE_MARKER}={shlex.quote(session)}; "
        f"echo $$ > {shlex.quote(str(pidfile))}; exec "
        + " ".join(shlex.quote(argument) for argument in command)
    )
    rules = f"[workspace name:{workspace} silent; noinitialfocus]"
    spawn = f"{rules} /bin/sh -c {shlex.quote(inner)}"
    try:
        subprocess.run(
            ["hyprctl", "dispatch", "exec", spawn],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        pidfile.unlink(missing_ok=True)
        raise ScreenError(
            "The staging launch could not be dispatched; retry with --no-stage"
        ) from error
    # The trampoline reports its pid as its first act, so this deadline is a
    # fixed internal one; the caller's --wait-seconds bounds the much slower
    # wait for a window to appear and must not shorten it.
    deadline = time.monotonic() + PID_TIMEOUT_SECONDS
    while True:
        try:
            recorded = pidfile.read_text(encoding="utf-8").strip()
        except OSError:
            recorded = ""
        if recorded.isdigit():
            pidfile.unlink(missing_ok=True)
            return int(recorded)
        if time.monotonic() >= deadline:
            pidfile.unlink(missing_ok=True)
            raise ScreenError(
                "The staging launch never reported a process id; retry with --no-stage"
            )
        time.sleep(POLL_SECONDS)


def sweep_stage_windows(session: str, pid: int, workspace: str) -> None:
    """Pull every window of one staged spawn back onto the stage. Best effort.

    The exec rule that placed the primary window is one-shot, so a window that
    mapped before the watcher could act — or while no watcher was running —
    sits on the user's own workspace. Ownership is decided the same way the
    watcher decides it: a descendant of the spawn, or a process carrying this
    session's marker. A client that reports no workspace at all is left alone:
    an unreported workspace is evidence of nothing, and a move is only ever
    justified by a confirmed miss.
    """
    live = lookup_clients() or []
    owned = descendant_pids(pid)
    for client in live:
        address = client.get("address")
        if not (isinstance(address, str) and address):
            continue
        placed = client.get("workspace")
        name = placed.get("name") if isinstance(placed, dict) else None
        if name is None or name == workspace:
            continue
        client_pid = client.get("pid")
        if not isinstance(client_pid, int):
            continue
        if client_pid not in owned and not has_stage_marker(client_pid, session):
            continue
        hyprctl_quiet(
            "dispatch",
            "movetoworkspacesilent",
            f"name:{workspace},address:{address}",
        )
