"""Hyprland, notification, theme-mode, and window-discovery integrations."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any

from .state import ScreenError


ADAPTER_COMMANDS = {
    "alacritty": ["alacritty", "--class", "Codex-visual-alacritty"],
    "neovim": ["alacritty", "--class", "Codex-visual-neovim", "-e", "nvim"],
    "btop": ["alacritty", "--class", "Codex-visual-btop", "-e", "btop"],
    "rofi": ["rofi", "-show", "drun"],
}
ADAPTER_NAMES = ("desktop", *ADAPTER_COMMANDS, "notification")


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


def expected_mode() -> str:
    try:
        result = subprocess.run(
            ["darkman", "get"], check=True, capture_output=True, text=True
        )
        value = result.stdout.strip()
        return value if value in {"dark", "light"} else "unknown"
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
