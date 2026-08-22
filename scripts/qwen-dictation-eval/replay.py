#!/usr/bin/env python3
"""Replay archived short-dictation audio through DashScope realtime under
several cleanup-prompt conditions.

For each selected wav in the short-dictation archive and each prompt file in
prompts/, this opens (and reuses) one realtime WebSocket session per
condition, streams the audio, commits, requests a text response, and records
the cleaned output, the provider's raw input-audio transcription, and
commit->final latency. Results go to a JSON file for score.py.

Uses the deployed dictation credentials read-only. Run with the shim's
Python environment (needs websockets), e.g.:

  $(systemctl --user cat qwen-asr-shim.service | sed -n 's/^ExecStart=//p' \
      | cut -d' ' -f1) replay.py --limit 20 --out results.json
"""

import argparse
import asyncio
import base64
import json
import os
import re
import subprocess
import sys
import time
import wave
from pathlib import Path

import websockets

QWEN_ASR_HOST = os.environ.get(
    "QWEN_ASR_HOST", "ws-dhkjvhwrwai1r9c5.cn-beijing.maas.aliyuncs.com"
)
MODEL = os.environ.get("QWEN_EVAL_MODEL", "qwen3.5-omni-plus-realtime")
WS_URL = f"wss://{QWEN_ASR_HOST}/api-ws/v1/realtime?model={MODEL}"
CREDENTIALS = os.path.expanduser(
    os.environ.get("QWEN_ASR_CREDENTIALS", "~/.local/share/hyprwhspr/credentials")
)
AUDIO_DIR = Path(
    os.environ.get(
        "QWEN_EVAL_AUDIO_DIR",
        os.path.expanduser("~/.local/share/hyprwhspr/short/audio"),
    )
)
PROMPTS_DIR = Path(__file__).resolve().parent / "prompts"
TARGET_RATE = 16000
CHUNK_BYTES = TARGET_RATE * 2 // 5  # 100 ms of PCM16 per append
RESPONSE_TIMEOUT = 60.0

_ENV_REF_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")


def get_api_key():
    with open(CREDENTIALS, "r", encoding="utf-8") as f:
        creds = json.load(f)
    value = creds["dashscope"]
    match = _ENV_REF_RE.match(value)
    if match:
        value = os.environ[match.group(1)]
    return value


def wav_duration(path):
    with wave.open(str(path), "rb") as w:
        return w.getnframes() / w.getframerate()


def select_utterances(limit, min_s=2.0, max_s=30.0):
    """Deterministic, evenly spread selection across the archive."""
    candidates = []
    for path in sorted(AUDIO_DIR.glob("*.wav")):
        try:
            duration = wav_duration(path)
        except Exception:
            continue
        if min_s <= duration <= max_s:
            candidates.append((path, duration))
    if len(candidates) <= limit:
        return candidates
    stride = len(candidates) / limit
    return [candidates[int(i * stride)] for i in range(limit)]


def decode_pcm16(path):
    """Decode any wav to 16 kHz mono PCM16 via ffmpeg."""
    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-i", str(path),
            "-f", "s16le", "-ar", str(TARGET_RATE), "-ac", "1", "-",
        ],
        capture_output=True,
        check=True,
    )
    return result.stdout


def session_update(instructions):
    session = {
        "modalities": ["text"],
        "input_audio_format": "pcm16",
        "turn_detection": None,
    }
    if instructions:
        session["instructions"] = instructions
    return {"type": "session.update", "session": session}


async def run_utterance(ws, pcm, raw_by_item):
    """Stream one utterance; return (cleaned, raw_asr, latency_ms).

    ``raw_by_item`` is per-connection state mapping audio item id to its raw
    input-audio transcription: those events lag and can arrive after
    response.done or even in the next utterance's window, so they are keyed
    by item id rather than attributed by arrival order.
    """
    for i in range(0, len(pcm), CHUNK_BYTES):
        await ws.send(json.dumps({
            "type": "input_audio_buffer.append",
            "audio": base64.b64encode(pcm[i:i + CHUNK_BYTES]).decode("ascii"),
        }))
    await ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
    commit_t = time.perf_counter()
    await ws.send(json.dumps({
        "type": "response.create",
        "response": {"modalities": ["text"]},
    }))

    cleaned = ""
    item_ids = []
    audio_ids = []
    latency_ms = None

    def handle(ev):
        t = ev.get("type", "")
        if t == "conversation.item.created":
            item_id = (ev.get("item") or {}).get("id")
            if item_id and item_id not in item_ids:
                item_ids.append(item_id)
        elif t == "input_audio_buffer.committed":
            # The committed audio item may never appear as
            # conversation.item.created; track it here like the shim does,
            # or it is never deleted and history accumulates.
            item_id = ev.get("item_id")
            if item_id:
                if item_id not in item_ids:
                    item_ids.append(item_id)
                if item_id not in audio_ids:
                    audio_ids.append(item_id)
        elif t == "conversation.item.input_audio_transcription.completed":
            transcript = (ev.get("transcript") or ev.get("text") or "").strip()
            item_id = ev.get("item_id")
            if item_id:
                raw_by_item[item_id] = transcript
        elif t == "error":
            raise RuntimeError(f"provider error: {ev}")
        return t

    deadline = time.monotonic() + RESPONSE_TIMEOUT
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("no response.done within timeout")
        ev = json.loads(await asyncio.wait_for(ws.recv(), remaining))
        t = handle(ev)
        if t == "response.text.done":
            cleaned = ev.get("text", "")
        elif t == "response.done":
            latency_ms = (time.perf_counter() - commit_t) * 1000
            break

    # Give the lagging raw transcription a short grace window.
    deadline = time.monotonic() + 3.0
    while any(item_id not in raw_by_item for item_id in audio_ids):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            ev = json.loads(await asyncio.wait_for(ws.recv(), remaining))
        except TimeoutError:
            break
        handle(ev)

    # Mirror the shim: drop conversation history so utterances stay
    # independent and tokens do not accumulate. Unlike the human-paced shim,
    # this replays back to back, so wait for the delete acknowledgements --
    # otherwise the next utterance's response covers accumulated history.
    for item_id in item_ids:
        await ws.send(json.dumps({
            "type": "conversation.item.delete",
            "item_id": item_id,
        }))
    deleted = 0
    deadline = time.monotonic() + 10.0
    while deleted < len(item_ids):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("conversation.item.delete not acknowledged")
        ev = json.loads(await asyncio.wait_for(ws.recv(), remaining))
        t = handle(ev)
        if t == "conversation.item.deleted":
            deleted += 1

    raw = " ".join(
        raw_by_item[item_id] for item_id in audio_ids if raw_by_item.get(item_id)
    )
    return cleaned, raw, latency_ms


async def run_condition(name, instructions, utterances, api_key, results):
    ws = None
    raw_by_item = {}
    for path, duration in utterances:
        pcm = decode_pcm16(path)
        for attempt in (1, 2):
            if ws is None:
                raw_by_item = {}
                ws = await websockets.connect(
                    WS_URL,
                    additional_headers={"Authorization": f"Bearer {api_key}"},
                    open_timeout=15,
                    max_size=None,
                )
                await ws.send(json.dumps(session_update(instructions)))
            try:
                cleaned, raw, latency_ms = await run_utterance(
                    ws, pcm, raw_by_item
                )
                break
            except (
                websockets.exceptions.ConnectionClosed,
                TimeoutError,
                RuntimeError,
            ) as e:
                print(f"  {name} {path.name}: {e}; reconnecting", file=sys.stderr)
                try:
                    await ws.close()
                except Exception:
                    pass
                ws = None
                if attempt == 2:
                    cleaned, raw, latency_ms = None, None, None
        entry = results.setdefault(path.name, {"duration_s": round(duration, 2)})
        entry[name] = {
            "text": cleaned,
            "raw_asr": raw,
            "latency_ms": round(latency_ms) if latency_ms else None,
        }
        shown = (cleaned or "").replace("\n", " ")[:70]
        print(f"  {name} {path.name} {latency_ms and round(latency_ms)}ms: {shown}")
    if ws is not None:
        await ws.close()


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--out", default="results.json")
    parser.add_argument(
        "--conditions",
        default=",".join(sorted(p.stem for p in PROMPTS_DIR.glob("*.txt"))),
    )
    args = parser.parse_args()

    api_key = get_api_key()
    utterances = select_utterances(args.limit)
    print(f"selected {len(utterances)} utterances from {AUDIO_DIR}")

    results = {}
    for condition in args.conditions.split(","):
        prompt_path = PROMPTS_DIR / f"{condition}.txt"
        instructions = prompt_path.read_text(encoding="utf-8").strip()
        print(f"condition {condition} ({len(instructions)} chars)")
        await run_condition(condition, instructions, utterances, api_key, results)
        # Checkpoint after each condition.
        Path(args.out).write_text(
            json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    print(f"wrote {args.out}")


if __name__ == "__main__":
    asyncio.run(main())
