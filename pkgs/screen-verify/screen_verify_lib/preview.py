"""Reversible visual previews owned by an ephemeral session."""

from __future__ import annotations

import argparse
import base64
import os
import stat
import subprocess
from pathlib import Path
from typing import Any

from .desktop import run_json
from .state import ScreenError, atomic_json, audit, read_json, session_dir


def home_path(value: str) -> Path:
    requested = Path(value).expanduser().absolute()
    home = Path.home().resolve()
    path = requested.parent.resolve() / requested.name
    try:
        path.relative_to(home)
    except ValueError as error:
        raise ScreenError("Preview targets must be inside the home directory") from error
    return path


def record_preview(path: Path, preview: dict[str, Any]) -> None:
    data = read_json(path / "session.json")
    data.setdefault("previews", []).append(preview)
    atomic_json(path / "session.json", data)


def command_preview_symlink(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    target = home_path(args.target)
    source = Path(args.source).expanduser().absolute()
    if not source.exists():
        raise ScreenError("Preview source does not exist")
    if target.is_symlink():
        original = {"state": "symlink", "value": os.readlink(target)}
    elif target.is_file():
        original = {
            "state": "file",
            "value": base64.b64encode(target.read_bytes()).decode("ascii"),
            "mode": stat.S_IMODE(target.stat().st_mode),
        }
    elif target.exists():
        raise ScreenError("Preview target must be a file, symlink, or missing")
    else:
        original = {"state": "missing"}
    record_preview(
        path,
        {"kind": "symlink", "target": str(target), "original": original},
    )
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f".{target.name}.screen-verify")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(source)
    temporary.replace(target)
    audit("preview", session=args.session)
    return {"preview": "symlink", "target": str(target)}


def command_preview_gsettings(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    try:
        original = subprocess.run(
            ["gsettings", "get", args.schema, args.key],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as error:
        raise ScreenError("Unable to snapshot the GSettings value") from error
    record_preview(
        path,
        {
            "kind": "gsettings",
            "schema": args.schema,
            "key": args.key,
            "original": original,
        },
    )
    subprocess.run(
        ["gsettings", "set", args.schema, args.key, args.value], check=True
    )
    audit("preview", session=args.session)
    return {"preview": "gsettings"}


def _lua_literal(value: str) -> str:
    """Render a keyword value as a Lua literal.

    Numbers and booleans go through bare so integer- and float-typed options
    keep their type; anything else becomes a double-quoted string.
    """
    if value in ("true", "false"):
        return value
    try:
        float(value)
    except ValueError:
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return value


def hypr_keyword_command(keyword: str, value: str) -> list[str]:
    """`hyprctl keyword <k> <v>` as a Lua eval.

    Hyprland's Lua config manager refuses `hyprctl keyword` outright ("keyword
    can't work with non-legacy parsers. Use eval."), so a keyword path like
    `general:col.active_border` is rebuilt as the nested `hl.config` table
    `{general = {col = {active_border = ...}}}`.
    """
    parts = [part for part in keyword.replace(":", ".").split(".") if part]
    if not parts:
        raise ScreenError("Empty Hyprland keyword")
    expression = _lua_literal(value)
    for part in reversed(parts):
        expression = f"{{ {part} = {expression} }}"
    return ["hyprctl", "eval", f"hl.config({expression})"]


def command_preview_hypr_keyword(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    option = run_json(["hyprctl", "getoption", args.keyword, "-j"])
    original = option.get("custom")
    if not isinstance(original, str):
        raise ScreenError("Unable to snapshot the Hyprland keyword")
    record_preview(
        path,
        {
            "kind": "hypr-keyword",
            "keyword": args.keyword,
            "original": original,
        },
    )
    subprocess.run(hypr_keyword_command(args.keyword, args.value), check=True)
    audit("preview", session=args.session)
    return {"preview": "hypr-keyword"}


def command_preview_mako_mode(args: argparse.Namespace) -> dict[str, Any]:
    path = session_dir(args.session)
    try:
        modes = subprocess.run(
            ["makoctl", "mode"], check=True, capture_output=True, text=True
        ).stdout.split()
    except (OSError, subprocess.CalledProcessError) as error:
        raise ScreenError("Unable to snapshot Mako modes") from error
    record_preview(path, {"kind": "mako-mode", "original": modes})
    subprocess.run(["makoctl", "mode", "-s", args.mode], check=True)
    audit("preview", session=args.session)
    return {"preview": "mako-mode"}


def restore_preview(preview: dict[str, Any]) -> None:
    kind = preview.get("kind")
    if kind == "symlink":
        target = home_path(preview["target"])
        original = preview["original"]
        temporary = target.with_name(f".{target.name}.screen-verify-restore")
        temporary.unlink(missing_ok=True)
        if original["state"] == "symlink":
            temporary.symlink_to(original["value"])
            temporary.replace(target)
        elif original["state"] == "file":
            temporary.write_bytes(base64.b64decode(original["value"]))
            temporary.chmod(original["mode"])
            temporary.replace(target)
        else:
            target.unlink(missing_ok=True)
        return
    if kind == "gsettings":
        subprocess.run(
            [
                "gsettings",
                "set",
                preview["schema"],
                preview["key"],
                preview["original"],
            ],
            check=True,
        )
        return
    if kind == "hypr-keyword":
        subprocess.run(
            hypr_keyword_command(preview["keyword"], preview["original"]),
            check=True,
        )
        return
    if kind == "mako-mode":
        subprocess.run(
            ["makoctl", "mode", "-s", *preview["original"]], check=True
        )
        return
    raise ScreenError("Session contains an unknown preview type")


def restore_previews(path: Path) -> int:
    data = read_json(path / "session.json")
    restored = 0
    for preview in reversed(data.get("previews", [])):
        try:
            restore_preview(preview)
            restored += 1
        except (OSError, KeyError, ValueError, subprocess.CalledProcessError) as error:
            raise ScreenError("Unable to restore preview state; session retained") from error
    return restored
