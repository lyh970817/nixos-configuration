#!/usr/bin/env python3
"""Replace the last pasted short dictation with its raw ASR transcript.

Reads the newest record from the per-dictation ring that qwen-asr-shim
maintains (~/.local/share/hyprwhspr/short/dictations.jsonl: raw ASR, cleaned
text, and the exact text hyprwhspr injected, reported by the paste-notify
patch). Erases the pasted text with one backspace per character, then pastes
the raw transcript using the same clipboard+hotkey strategy as the long-form
path. Bound to Super+Shift+O.

Skipped with a warning when raw coverage is partial (the Qwen Audio3
multi-commit path can emit raw transcription for only some committed items),
when nothing was pasted, or when the record was already reverted.

Erasure counts characters, so it is only safe immediately after the paste and
cannot cross an already-submitted terminal newline. Requires wl-copy, wtype,
hyprctl, and notify-send on PATH (provided by the Home Manager wrapper).
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

RING_PATH = Path(
    os.environ.get("QWEN_DICTATION_RING_PATH")
    or Path.home() / ".local/share/hyprwhspr/short/dictations.jsonl"
)
BACKSPACE_CHUNK = 200


def notify(title, body=""):
    subprocess.run(
        ["notify-send", title, body],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def fail(title, body=""):
    print(f"{title}: {body}" if body else title, file=sys.stderr)
    notify(title, body)
    return 1


def load_ring():
    try:
        text = RING_PATH.read_text(encoding="utf-8")
    except FileNotFoundError:
        return []
    entries = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except ValueError:
            continue
    return entries


def save_ring(entries):
    tmp_path = RING_PATH.with_suffix(".jsonl.tmp")
    tmp_path.write_text(
        "\n".join(json.dumps(entry, ensure_ascii=False) for entry in entries)
        + "\n",
        encoding="utf-8",
    )
    tmp_path.chmod(0o600)
    os.replace(tmp_path, RING_PATH)


def active_window_class():
    try:
        result = subprocess.run(
            ["hyprctl", "-j", "activewindow"],
            text=True,
            capture_output=True,
            timeout=2,
            check=True,
        )
        data = json.loads(result.stdout)
    except Exception:
        return ""
    value = data.get("class") or data.get("initialClass") or ""
    return value.lower() if isinstance(value, str) else ""


def paste_keys():
    try:
        return json.loads(os.environ.get("HYPRWHSPR_REVERT_PASTE_KEYS") or "{}")
    except ValueError:
        return {}


def key_combo_args(combo):
    parts = [part.strip().lower() for part in combo.split("+") if part.strip()]
    modifiers = [part for part in parts if part in {"ctrl", "shift", "alt", "super"}]
    keys = [part for part in parts if part not in modifiers]
    key = keys[-1] if keys else "v"

    args = []
    for modifier in modifiers:
        args.extend(["-M", modifier])
    args.extend(["-k", key])
    for modifier in reversed(modifiers):
        args.extend(["-m", modifier])
    return args


def erase_chars(count):
    remaining = count
    while remaining > 0:
        chunk = min(remaining, BACKSPACE_CHUNK)
        args = ["wtype"]
        for _ in range(chunk):
            args.extend(["-k", "BackSpace"])
        subprocess.run(args, check=True)
        remaining -= chunk


def paste_text(text):
    subprocess.run(["wl-copy"], input=text, text=True, check=True)
    time.sleep(0.12)
    combo = paste_keys().get(active_window_class(), "ctrl+v")
    subprocess.run(["wtype"] + key_combo_args(combo), check=True)


def main():
    entries = load_ring()
    if not entries:
        return fail("Dictation revert", "No recorded dictations")

    last = entries[-1]
    if last.get("reverted"):
        return fail("Dictation revert", "Last dictation already reverted")
    pasted = last.get("pasted")
    if not pasted:
        return fail("Dictation revert", "Last dictation was not pasted")
    raw = (last.get("raw") or "").strip()
    if not raw:
        return fail("Dictation revert", "No raw transcript was recorded")
    if last.get("raw_partial"):
        return fail(
            "Dictation revert skipped",
            "Raw transcript covers only part of the dictation",
        )

    # Match hyprwhspr's injection conventions: newlines normalized to spaces,
    # one trailing space.
    replacement = " ".join(raw.split()) + " "

    try:
        erase_chars(len(pasted))
        paste_text(replacement)
    except Exception as e:
        return fail("Dictation revert failed", str(e))

    last["reverted"] = True
    try:
        save_ring(entries)
    except Exception as e:
        print(f"failed to mark record reverted: {e}", file=sys.stderr)

    notify("Dictation reverted", "Replaced with raw transcript")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
