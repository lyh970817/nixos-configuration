#!/usr/bin/env python3
"""Qwen (DashScope) ASR shim for hyprwhspr's "rest-api" transcription backend.

hyprwhspr POSTs multipart/form-data (fields: file=<wav bytes>, prompt=<vocab
context, may be absent/empty>, plus other scalar fields to ignore) and expects
back JSON {"text": "..."} with HTTP 200, or HTTP 500 with {"error": "..."} on
failure.

This shim exposes three routes that all transcribe via Alibaba Cloud
DashScope's Qwen models, using different underlying protocols:

  POST /transcribe/http  - single chat/completions call, raw ASR only
  POST /transcribe/ws    - realtime websocket ASR + a chat/completions
                           cleanup pass over the raw transcript
  POST /transcribe/omni  - single chat/completions call against an omni
                           model that both transcribes and cleans up
  POST /prewarm          - ensure the pooled DashScope connection is live
                           (returns 204 immediately, warms in the background)
  GET  /health           - liveness check

Intended to run as a small long-lived local service (e.g. under a systemd
user unit, configured elsewhere) fronting hyprwhspr's REST backend.

Latency notes: outbound DashScope calls go through a single keep-alive
connection pool (kept warm by a background heartbeat and the /prewarm hook)
so the common case skips the TCP+TLS handshake, and the common WAV input is
decoded/resampled/trimmed in-process instead of via an ffmpeg subprocess.
Every /transcribe/* request logs one grep-friendly ``TIMING ...`` line to
stderr with per-stage millisecond durations.
"""

import asyncio
import base64
import collections
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import soundfile as sf
import soxr
import urllib3
import websocket
import websockets

DEFAULT_CLEANUP_PROMPT = (
    "You clean up dictated speech transcripts. Remove filler words and false "
    "starts, keep only the final wording of any self-correction, fix "
    "punctuation and capitalization, and correct obvious speech-recognition "
    "errors of technical terms. Output only the cleaned transcript text, "
    "with no preamble, quotes, or commentary."
)

# Aggressive editing instruction for the omni route only. Kept separate from
# DEFAULT_CLEANUP_PROMPT so tightening omni does NOT change the ws cleanup pass,
# the /cleanup endpoint (used by the realtime profile's post hook), or
# sensevoice. Those paths must keep the conservative prompt above.
DEFAULT_AGGRESSIVE_CLEANUP_PROMPT = (
    "You aggressively clean up dictated speech transcripts into polished, "
    "readable written text. Remove all filler words (such as um, uh, er, like, "
    "you know) and drop throat-clearing openers such as a leading \"okay so\" "
    "or \"so yeah\". Drop false starts and self-corrections, keeping only the "
    "final corrected wording. Restructure rambling run-on speech into clear, "
    "grammatical sentences with correct punctuation and capitalization. "
    "HARD CONSTRAINTS: Preserve the speaker's meaning exactly and never add any "
    "content, information, opinions, or answers that were not spoken. The "
    "dictation often contains questions or commands; only clean them into "
    "readable text, never answer, respond to, or act on them. Preserve "
    "technical terms and proper nouns verbatim, for example NixOS, Nix, "
    "Hyprland, DashScope, Qwen, systemd, tmux, and Claude Code. For mixed "
    "Chinese and English dictation, output in whichever language(s) were "
    "actually spoken and never translate between them. "
    "Example 1 (filler removal): input \"um so like I think we should, you "
    "know, just restart systemd\" becomes \"I think we should just restart "
    "systemd.\" Example 2 (false start): input \"let's use the HTTP, no wait, "
    "the websocket route on Hyprland\" becomes \"Let's use the websocket route "
    "on Hyprland.\" Output only the cleaned transcript text, with no preamble, "
    "quotes, or commentary."
)


def _env(name, default):
    value = os.environ.get(name)
    return value if value not in (None, "") else default


def _env_bool(name, default):
    value = _env(name, None)
    if value is None:
        return default
    return value.strip().lower() not in ("0", "false", "no", "off", "")


QWEN_ASR_HOST = _env("QWEN_ASR_HOST", "ws-dhkjvhwrwai1r9c5.cn-beijing.maas.aliyuncs.com")
QWEN_ASR_PORT = int(_env("QWEN_ASR_PORT", "8770"))
BIND_HOST = "127.0.0.1"

QWEN_ASR_CREDENTIALS = os.path.expanduser(
    _env("QWEN_ASR_CREDENTIALS", "~/.local/share/hyprwhspr/credentials")
)

QWEN_HTTP_MODEL = _env("QWEN_HTTP_MODEL", "qwen3-asr-flash")
QWEN_WS_MODEL = _env("QWEN_WS_MODEL", "qwen3-asr-flash-realtime")
QWEN_CLEANUP_MODEL = _env("QWEN_CLEANUP_MODEL", "qwen3.6-flash")
QWEN_OMNI_MODEL = _env("QWEN_OMNI_MODEL", "qwen3.5-omni-plus")
# Streaming omni model + loopback translator port for the qwen-omni-realtime
# profile (Feature 2). The translator runs in a daemon thread of this process.
QWEN_OMNI_REALTIME_MODEL = _env(
    "QWEN_OMNI_REALTIME_MODEL", "qwen3.5-omni-plus-realtime"
)
QWEN_TRANSLATOR_PORT = int(_env("QWEN_TRANSLATOR_PORT", "8771"))
QWEN_ASR_LANGUAGE = _env("QWEN_ASR_LANGUAGE", "en")
QWEN_CLEANUP_PROMPT = _env("QWEN_CLEANUP_PROMPT", DEFAULT_CLEANUP_PROMPT)
QWEN_AGGRESSIVE_CLEANUP_PROMPT = _env(
    "QWEN_AGGRESSIVE_CLEANUP_PROMPT", DEFAULT_AGGRESSIVE_CLEANUP_PROMPT
)
QWEN_CHAT_TIMEOUT = float(_env("QWEN_CHAT_TIMEOUT", "25"))
QWEN_WS_TIMEOUT = float(_env("QWEN_WS_TIMEOUT", "25"))
# Settle window after the last audio append and before input_audio_buffer.commit.
# The recording is replayed unpaced, so without a brief pause the commit races
# ahead of DashScope ingesting the just-sent frames and the server rejects it as
# an empty/invalid buffer ("Error committing input audio buffer").
QWEN_WS_COMMIT_SETTLE = float(_env("QWEN_WS_COMMIT_SETTLE", "0.5"))

# Connection pool / warmth tuning.
QWEN_CONNECT_TIMEOUT = float(_env("QWEN_CONNECT_TIMEOUT", "5"))
QWEN_POOL_MAXSIZE = int(_env("QWEN_POOL_MAXSIZE", "4"))
QWEN_KEEPALIVE_SECONDS = float(_env("QWEN_KEEPALIVE_SECONDS", "50"))
QWEN_WARM_TIMEOUT = float(_env("QWEN_WARM_TIMEOUT", "8"))

# In-process audio prep tuning.
TARGET_RATE = 16000
QWEN_TRIM_SILENCE = _env_bool("QWEN_TRIM_SILENCE", True)
_TRIM_FRAME_MS = 20
_TRIM_MARGIN_MS = 200
_TRIM_REL = 0.03  # voiced when frame RMS exceeds 3% of the loudest frame ...
_TRIM_FLOOR = 80.0  # ... but never below this absolute int16 RMS floor.

CHAT_COMPLETIONS_PATH = "/compatible-mode/v1/chat/completions"
MODELS_PATH = "/compatible-mode/v1/models"
CHAT_COMPLETIONS_URL = f"https://{QWEN_ASR_HOST}{CHAT_COMPLETIONS_PATH}"
REALTIME_WS_URL = f"wss://{QWEN_ASR_HOST}/api-ws/v1/realtime?model={QWEN_WS_MODEL}"
QWEN_OMNI_REALTIME_WS_URL = (
    f"wss://{QWEN_ASR_HOST}/api-ws/v1/realtime?model={QWEN_OMNI_REALTIME_MODEL}"
)

_ENV_REF_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$")


def log(msg):
    print(f"[qwen-asr-shim] {msg}", file=sys.stderr, flush=True)


def get_api_key():
    """Read the DashScope API key from the credentials JSON file.

    The value at key "dashscope" is used literally unless it matches
    ``${SOME_ENV_VAR}``, in which case it is resolved from the environment.
    """
    with open(QWEN_ASR_CREDENTIALS, "r", encoding="utf-8") as f:
        creds = json.load(f)
    value = creds["dashscope"]
    match = _ENV_REF_RE.match(value)
    if match:
        var_name = match.group(1)
        try:
            value = os.environ[var_name]
        except KeyError:
            raise RuntimeError(
                f"credentials file references ${{{var_name}}} but that "
                f"environment variable is not set"
            ) from None
    return value


# --------------------------------------------------------------------------
# Minimal multipart/form-data parsing (no cgi/email module tricks)
# --------------------------------------------------------------------------

def get_multipart_boundary(content_type):
    match = re.search(r'boundary="?([^";]+)"?', content_type or "")
    if not match:
        raise ValueError("Content-Type has no multipart boundary")
    return match.group(1)


def parse_multipart(body, boundary):
    """Parse multipart/form-data bytes into {name: {"data": bytes, "filename": str|None}}."""
    delimiter = ("--" + boundary).encode("utf-8")
    fields = {}
    for part in body.split(delimiter):
        if not part or part.startswith(b"--"):
            # empty preamble, or the closing "--boundary--" marker
            continue
        if not part.startswith(b"\r\n"):
            continue
        part = part[2:]
        if part.endswith(b"\r\n"):
            part = part[:-2]
        header_end = part.find(b"\r\n\r\n")
        if header_end == -1:
            continue
        header_text = part[:header_end].decode("utf-8", errors="replace")
        content = part[header_end + 4:]
        name_match = re.search(r'name="([^"]*)"', header_text)
        if not name_match:
            continue
        filename_match = re.search(r'filename="([^"]*)"', header_text)
        fields[name_match.group(1)] = {
            "data": content,
            "filename": filename_match.group(1) if filename_match else None,
        }
    return fields


# --------------------------------------------------------------------------
# In-process audio preparation (decode -> mono -> 16k -> trim), with an
# ffmpeg subprocess as the fallback for anything the fast path can't parse.
# --------------------------------------------------------------------------

def _run_ffmpeg(args):
    try:
        return subprocess.run(args, check=True, capture_output=True)
    except FileNotFoundError:
        raise RuntimeError("ffmpeg binary not found on PATH") from None
    except subprocess.CalledProcessError as e:
        stderr = e.stderr.decode("utf-8", errors="replace")[:300] if e.stderr else ""
        raise RuntimeError(f"ffmpeg failed (exit {e.returncode}): {stderr}") from None


def _decode_via_ffmpeg(input_bytes):
    """Fallback decoder: resample arbitrary input to 16k mono s16le via ffmpeg."""
    in_path = tempfile.mktemp(suffix=".in")
    try:
        with open(in_path, "wb") as f:
            f.write(input_bytes)
        result = _run_ffmpeg(
            ["ffmpeg", "-y", "-i", in_path, "-ar", str(TARGET_RATE), "-ac", "1", "-f", "s16le", "-"]
        )
        return np.frombuffer(result.stdout, dtype="<i2").copy()
    finally:
        try:
            os.remove(in_path)
        except OSError:
            pass


def _decode_wav_fast(input_bytes):
    """Parse a PCM WAV in-process to a 16k mono int16 array.

    Raises on anything the stdlib ``wave`` reader can't handle (e.g. non-WAV
    containers or IEEE-float WAVs), so callers fall back to ffmpeg.
    """
    with wave.open(io.BytesIO(input_bytes), "rb") as w:
        n_channels = w.getnchannels()
        sampwidth = w.getsampwidth()
        framerate = w.getframerate()
        raw = w.readframes(w.getnframes())

    if sampwidth == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif sampwidth == 1:
        # WAV 8-bit PCM is unsigned, centred on 128.
        data = (np.frombuffer(raw, dtype=np.uint8).astype(np.float32) - 128.0) / 128.0
    elif sampwidth == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    elif sampwidth == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        ints = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        ints = np.where(ints & 0x800000, ints - 0x1000000, ints)
        data = ints.astype(np.float32) / 8388608.0
    else:
        raise ValueError(f"unsupported WAV sample width {sampwidth}")

    if n_channels > 1:
        data = data.reshape(-1, n_channels).mean(axis=1)
    if framerate != TARGET_RATE:
        data = soxr.resample(data, framerate, TARGET_RATE)
    return np.clip(data * 32768.0, -32768, 32767).astype("<i2")


def _trim_silence(samples):
    """Energy-trim leading/trailing silence, keeping ~200ms of margin each side.

    Returns (trimmed_samples, trimmed_seconds).
    """
    frame = int(TARGET_RATE * _TRIM_FRAME_MS / 1000)
    n_frames = len(samples) // frame
    if n_frames == 0:
        return samples, 0.0

    frames = samples[: n_frames * frame].astype(np.float32).reshape(n_frames, frame)
    rms = np.sqrt(np.mean(frames * frames, axis=1))
    peak = float(rms.max())
    if peak <= 0.0:
        return samples, 0.0

    threshold = max(peak * _TRIM_REL, _TRIM_FLOOR)
    voiced = np.nonzero(rms > threshold)[0]
    if len(voiced) == 0:
        return samples, 0.0

    margin = int(_TRIM_MARGIN_MS / _TRIM_FRAME_MS)
    start = max(0, int(voiced[0]) - margin) * frame
    end = min(n_frames, int(voiced[-1]) + 1 + margin) * frame
    trimmed = samples[start:end]
    trimmed_s = (len(samples) - len(trimmed)) / TARGET_RATE
    return trimmed, trimmed_s


class PreparedAudio:
    """16k mono int16 PCM, ready to send as raw bytes or wrap in a WAV header."""

    def __init__(self, samples):
        self.samples = samples

    @property
    def pcm_bytes(self):
        return self.samples.tobytes()

    @property
    def seconds(self):
        return len(self.samples) / TARGET_RATE

    def wav_bytes(self):
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(TARGET_RATE)
            w.writeframes(self.pcm_bytes)
        return buf.getvalue()


def prepare_audio(audio_bytes, timings):
    """Decode/resample/trim ``audio_bytes`` to a PreparedAudio, recording stage
    timings (``prep`` ms, ``decode`` method, ``trim_s``, ``audio_s``) into the
    ``timings`` dict for the request's TIMING line."""
    t0 = time.perf_counter()
    try:
        samples = _decode_wav_fast(audio_bytes)
        method = "fast"
    except Exception:
        samples = _decode_via_ffmpeg(audio_bytes)
        method = "ffmpeg"

    if QWEN_TRIM_SILENCE:
        samples, trimmed_s = _trim_silence(samples)
    else:
        trimmed_s = 0.0

    timings["decode"] = method
    timings["trim_s"] = trimmed_s
    timings["audio_s"] = len(samples) / TARGET_RATE
    timings["prep"] = (time.perf_counter() - t0) * 1000
    return PreparedAudio(samples)


# --------------------------------------------------------------------------
# DashScope chat/completions over a keep-alive connection pool
# --------------------------------------------------------------------------

# A single pool to the DashScope host; reused across requests so the common
# case skips the TCP+TLS handshake. num_connections increments only when the
# pool has to open a fresh socket, which we sample to report connection reuse.
_POOL = urllib3.HTTPSConnectionPool(
    QWEN_ASR_HOST,
    port=443,
    maxsize=QWEN_POOL_MAXSIZE,
    block=False,
    retries=False,
)

# Connection-level failures worth one silent retry (a pooled socket the peer
# closed while idle); read timeouts are deliberately excluded so a slow call
# is not silently doubled.
_RETRYABLE = (
    urllib3.exceptions.ProtocolError,
    urllib3.exceptions.NewConnectionError,
    urllib3.exceptions.ClosedPoolError,
    ConnectionError,
)


def _pool_request(method, path, api_key, body=None, timeout=QWEN_CHAT_TIMEOUT):
    """Send a request over the shared pool, retrying once on a stale socket.

    Returns (urllib3 response, reused) where ``reused`` is 1 when no new
    connection was opened for this call (best-effort under concurrency).
    """
    headers = {"Authorization": f"Bearer {api_key}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    urllib3_timeout = urllib3.Timeout(connect=QWEN_CONNECT_TIMEOUT, read=timeout)

    last_exc = None
    for _ in range(2):
        before = _POOL.num_connections
        try:
            resp = _POOL.urlopen(
                method,
                path,
                body=body,
                headers=headers,
                timeout=urllib3_timeout,
                retries=False,
                redirect=False,
                preload_content=True,
            )
        except _RETRYABLE as e:
            last_exc = e
            continue
        reused = 1 if _POOL.num_connections == before else 0
        return resp, reused

    raise RuntimeError(f"DashScope connection failed after retry: {last_exc}")


# Token usage for one chat/completions call. reasoning_tokens defaults to 0
# when DashScope doesn't report a completion_tokens_details.reasoning_tokens
# field; reasoning_seen additionally flags reasoning_content / <think> tags
# in the message body, since a model can think without the token count being
# broken out, which would otherwise make reasoning_tokens=0 misleading.
ChatUsage = collections.namedtuple(
    "ChatUsage",
    ["prompt_tokens", "completion_tokens", "reasoning_tokens", "reasoning_seen"],
)

_THINK_TAG_RE = re.compile(r"<think>", re.IGNORECASE)


def chat_completion(model, messages, api_key, extra=None, timeout=QWEN_CHAT_TIMEOUT):
    """Call chat/completions over the pool; returns (content, reused, usage)."""
    body = {"model": model, "messages": messages, "stream": False}
    if extra:
        body.update(extra)
    data = json.dumps(body).encode("utf-8")

    resp, reused = _pool_request(
        "POST", CHAT_COMPLETIONS_PATH, api_key, body=data, timeout=timeout
    )
    if resp.status != 200:
        detail = resp.data.decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"chat/completions HTTP {resp.status}: {detail}")

    try:
        payload = json.loads(resp.data)
    except (TypeError, ValueError):
        raise RuntimeError("chat/completions returned invalid JSON") from None
    try:
        message = payload["choices"][0]["message"]
        content = message["content"]
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(
            f"unexpected chat/completions response shape: {json.dumps(payload)[:300]}"
        ) from None

    usage_raw = payload.get("usage") or {}
    completion_details = usage_raw.get("completion_tokens_details") or {}
    reasoning_seen = bool(message.get("reasoning_content")) or bool(
        _THINK_TAG_RE.search(content or "")
    )
    usage = ChatUsage(
        prompt_tokens=usage_raw.get("prompt_tokens", 0) or 0,
        completion_tokens=usage_raw.get("completion_tokens", 0) or 0,
        reasoning_tokens=completion_details.get("reasoning_tokens", 0) or 0,
        reasoning_seen=reasoning_seen,
    )
    return content, reused, usage


def warm_pool():
    """Ensure the pool holds a live connection by pinging the models endpoint.

    Returns ``reused``; raises on failure so callers can log it.
    """
    api_key = get_api_key()
    resp, reused = _pool_request("GET", MODELS_PATH, api_key, timeout=QWEN_WARM_TIMEOUT)
    resp.drain_conn()
    if resp.status >= 400:
        raise RuntimeError(f"models ping HTTP {resp.status}")
    return reused


def keepalive_loop():
    """Background heartbeat that keeps the pool warm; never crashes the service."""
    while True:
        time.sleep(QWEN_KEEPALIVE_SECONDS)
        try:
            warm_pool()
        except Exception as e:
            log(f"keepalive warm failed (ignored): {e}")


def build_cleanup_instruction(prompt):
    text = QWEN_CLEANUP_PROMPT
    if prompt:
        text = f"{text} Known vocabulary and context: {prompt}"
    return text


def build_aggressive_cleanup_instruction(prompt):
    """Aggressive-editing instruction for the omni route only.

    Deliberately separate from build_cleanup_instruction so the omni behavior
    can be tightened without affecting the ws cleanup pass, the /cleanup
    endpoint, or sensevoice.
    """
    text = QWEN_AGGRESSIVE_CLEANUP_PROMPT
    if prompt:
        text = f"{text} Known vocabulary and context: {prompt}"
    return text


# --------------------------------------------------------------------------
# DashScope realtime websocket ASR (batch mode: stream a whole recording,
# then collect the final transcript)
# --------------------------------------------------------------------------

def transcribe_via_websocket(pcm, api_key, timeout=QWEN_WS_TIMEOUT):
    events = []
    final_chunks = []
    error_holder = []
    done = threading.Event()

    def on_open(ws):
        ws.send(json.dumps({
            "type": "session.update",
            "session": {
                "modalities": ["text"],
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "input_audio_transcription": {"language": QWEN_ASR_LANGUAGE},
                "turn_detection": {"type": "server_vad", "silence_duration_ms": 500},
            },
        }))

        def stream():
            # Brief settle so session.update is applied before audio arrives.
            time.sleep(0.3)
            # The recording is already complete, so replay it back-to-back;
            # chunking only bounds per-frame size, it is not real-time paced.
            chunk_size = 3200  # 100ms of 16k mono s16le
            for i in range(0, len(pcm), chunk_size):
                ws.send(json.dumps({
                    "type": "input_audio_buffer.append",
                    "audio": base64.b64encode(pcm[i:i + chunk_size]).decode(),
                }))
            # Single pre-commit settle so the server finishes ingesting the
            # frames we just appended before we commit; otherwise the commit
            # races ahead and DashScope rejects the buffer as empty/invalid.
            if QWEN_WS_COMMIT_SETTLE > 0:
                time.sleep(QWEN_WS_COMMIT_SETTLE)
            ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
            ws.send(json.dumps({"type": "session.finish"}))

        threading.Thread(target=stream, daemon=True).start()

    def on_message(ws, msg):
        try:
            event = json.loads(msg)
        except (TypeError, ValueError):
            return
        event_type = event.get("type", "?")
        events.append(event_type)
        if event_type.endswith("input_audio_transcription.completed"):
            final_chunks.append(event.get("transcript") or event.get("text"))
        if event_type == "error":
            error_holder.append(event)
            done.set()
        if event_type == "session.finished":
            done.set()

    def on_error(ws, err):
        error_holder.append(str(err))
        done.set()

    def on_close(ws, close_status_code, close_msg):
        done.set()

    ws_app = websocket.WebSocketApp(
        REALTIME_WS_URL,
        header=[f"Authorization: Bearer {api_key}", "OpenAI-Beta: realtime=v1"],
        on_open=on_open,
        on_message=on_message,
        on_error=on_error,
        on_close=on_close,
    )
    worker = threading.Thread(target=ws_app.run_forever, daemon=True)
    worker.start()
    finished = done.wait(timeout=timeout)
    try:
        ws_app.close()
    except Exception:
        pass

    if error_holder:
        raise RuntimeError(f"realtime websocket error: {error_holder[0]}")
    if not finished:
        raise RuntimeError(f"realtime websocket timed out after {timeout}s (events seen: {events})")
    if not final_chunks:
        raise RuntimeError(f"realtime websocket produced no transcript (events seen: {events})")

    return " ".join(str(chunk) for chunk in final_chunks if chunk)


# --------------------------------------------------------------------------
# Route handlers
# --------------------------------------------------------------------------

def _record_usage(timings, usage, output_text):
    """Fold a ChatUsage plus the returned text into the request's timings dict
    so format_timing() can emit grep-friendly token/char TIMING fields."""
    timings["in_tok"] = usage.prompt_tokens
    timings["out_tok"] = usage.completion_tokens
    timings["think_tok"] = usage.reasoning_tokens
    timings["think_seen"] = int(usage.reasoning_seen)
    timings["out_chars"] = len(output_text or "")


def handle_transcribe_http(audio_bytes, prompt, api_key, timings):
    audio = prepare_audio(audio_bytes, timings)
    b64 = base64.b64encode(audio.wav_bytes()).decode()

    messages = []
    if prompt:
        messages.append({"role": "system", "content": [{"type": "text", "text": prompt}]})
    messages.append({
        "role": "user",
        "content": [{
            "type": "input_audio",
            "input_audio": {"data": f"data:audio/wav;base64,{b64}", "format": "wav"},
        }],
    })

    t0 = time.perf_counter()
    text, reused, usage = chat_completion(QWEN_HTTP_MODEL, messages, api_key)
    timings["api"] = (time.perf_counter() - t0) * 1000
    timings["reused_conn"] = reused
    _record_usage(timings, usage, text)
    return text


def handle_transcribe_ws(audio_bytes, prompt, api_key, timings):
    audio = prepare_audio(audio_bytes, timings)

    t0 = time.perf_counter()
    raw_transcript = transcribe_via_websocket(audio.pcm_bytes, api_key)
    timings["ws"] = (time.perf_counter() - t0) * 1000

    messages = [
        {"role": "system", "content": build_cleanup_instruction(prompt)},
        {"role": "user", "content": raw_transcript},
    ]
    t1 = time.perf_counter()
    text, reused, usage = chat_completion(
        QWEN_CLEANUP_MODEL,
        messages,
        api_key,
        extra={"temperature": 0, "enable_thinking": False},
    )
    timings["cleanup"] = (time.perf_counter() - t1) * 1000
    timings["reused_conn"] = reused
    _record_usage(timings, usage, text)
    return text


def _encode_opus(samples):
    """Encode 16k mono int16 samples to Ogg/Opus bytes in-process.

    soundfile/libsndfile writes the compressed Ogg/Opus container directly from
    the numpy array, so the omni upload skips the ~8-11x larger base64 WAV. Opus
    natively supports the 16k rate used here. int16 input is accepted by
    sf.write, which converts to the codec's internal representation.
    """
    buf = io.BytesIO()
    sf.write(buf, samples, TARGET_RATE, format="OGG", subtype="OPUS")
    return buf.getvalue()


def handle_transcribe_omni(audio_bytes, prompt, api_key, timings):
    audio = prepare_audio(audio_bytes, timings)

    t_enc = time.perf_counter()
    opus_bytes = _encode_opus(audio.samples)
    timings["enc_ms"] = (time.perf_counter() - t_enc) * 1000
    b64 = base64.b64encode(opus_bytes).decode()

    messages = [
        {"role": "system", "content": build_aggressive_cleanup_instruction(prompt)},
        {
            "role": "user",
            "content": [{
                "type": "input_audio",
                "input_audio": {"data": f"data:audio/ogg;base64,{b64}", "format": "opus"},
            }],
        },
    ]
    t0 = time.perf_counter()
    text, reused, usage = chat_completion(
        QWEN_OMNI_MODEL,
        messages,
        api_key,
        extra={"modalities": ["text"], "temperature": 0, "enable_thinking": False},
    )
    timings["api"] = (time.perf_counter() - t0) * 1000
    timings["reused_conn"] = reused
    _record_usage(timings, usage, text)
    return text


ROUTE_HANDLERS = {
    "/transcribe/http": (QWEN_HTTP_MODEL, handle_transcribe_http),
    "/transcribe/ws": (f"{QWEN_WS_MODEL}+{QWEN_CLEANUP_MODEL}", handle_transcribe_ws),
    "/transcribe/omni": (QWEN_OMNI_MODEL, handle_transcribe_omni),
}


def format_timing(route, timings):
    """Build the grep-friendly per-request TIMING line from a timings dict."""
    name = route.rsplit("/", 1)[-1]
    fields = [f"route={name}"]
    for key in ("prep", "api", "ws", "cleanup", "total"):
        if key in timings:
            fields.append(f"{key}={timings[key]:.0f}")
    if "enc_ms" in timings:
        fields.append(f"enc_ms={timings['enc_ms']:.0f}")
    if "audio_s" in timings:
        fields.append(f"audio_s={timings['audio_s']:.2f}")
    if "trim_s" in timings:
        fields.append(f"trim_s={timings['trim_s']:.2f}")
    if "decode" in timings:
        fields.append(f"decode={timings['decode']}")
    if "reused_conn" in timings:
        fields.append(f"reused_conn={timings['reused_conn']}")
    if "in_tok" in timings:
        fields.append(f"in_tok={timings['in_tok']}")
    if "out_tok" in timings:
        fields.append(f"out_tok={timings['out_tok']}")
    if "think_tok" in timings:
        fields.append(f"think_tok={timings['think_tok']}")
    if "think_seen" in timings:
        fields.append(f"think_seen={timings['think_seen']}")
    if "out_chars" in timings:
        fields.append(f"out_chars={timings['out_chars']}")
    return "TIMING " + " ".join(fields)


# --------------------------------------------------------------------------
# omni-realtime WS translator (loopback) for the qwen-omni-realtime profile
#
# hyprwhspr's realtime-ws converse client connects here over loopback; this
# translator relays to the DashScope omni-realtime upstream, adapting message
# shapes both ways so hyprwhspr's converse dialect drives the omni model, which
# transcribes AND cleans in a single streaming session. The cleanup instruction
# is the SAME one the omni HTTP route uses (build_aggressive_cleanup_instruction)
# so a future prompt change flows to both paths from one place.
#
# It runs in its own daemon thread with a private asyncio event loop, kept fully
# separate from the sync ThreadingHTTPServer and its keep-alive connection pool.
# --------------------------------------------------------------------------

# Set once the translator's event loop is running so the sync /prewarm handler
# (an HTTP worker thread) can schedule a warm upstream via run_coroutine_threadsafe.
_TRANSLATOR_LOOP = None
# One best-effort pre-established upstream, adopted by the next client. The lock
# is created on the translator loop in translator_thread().
_WARM_UPSTREAM = {"ws": None}
_WARM_LOCK = None


def _flat_session_update():
    """The FLAT session.update the omni-realtime upstream requires; it rejects
    hyprwhspr's nested realtime shape. turn_detection MUST be explicitly null so
    server VAD does not fight hyprwhspr's manual commit + response.create flow."""
    return {
        "type": "session.update",
        "session": {
            "modalities": ["text"],
            "instructions": build_aggressive_cleanup_instruction(""),
            "input_audio_format": "pcm16",
            "turn_detection": None,
        },
    }


async def _open_upstream():
    """Open a fresh upstream omni-realtime connection and send session.update."""
    api_key = get_api_key()
    ws = await websockets.connect(
        QWEN_OMNI_REALTIME_WS_URL,
        additional_headers={"Authorization": f"Bearer {api_key}"},
        open_timeout=QWEN_WARM_TIMEOUT,
        max_size=None,
        ping_interval=20,
        ping_timeout=20,
    )
    await ws.send(json.dumps(_flat_session_update()))
    return ws


async def _warm_upstream_slot():
    """Best-effort: pre-establish one warm upstream for the next client."""
    async with _WARM_LOCK:
        if _WARM_UPSTREAM["ws"] is not None:
            return
    try:
        ws = await _open_upstream()
    except Exception as e:
        log(f"translator prewarm: upstream connect failed (ignored): {e}")
        return
    async with _WARM_LOCK:
        if _WARM_UPSTREAM["ws"] is None:
            _WARM_UPSTREAM["ws"] = ws
            log("translator prewarm: warm upstream ready")
            return
    await ws.close()


async def _acquire_upstream():
    """Adopt the warm upstream if present, else open a fresh one."""
    async with _WARM_LOCK:
        ws = _WARM_UPSTREAM["ws"]
        _WARM_UPSTREAM["ws"] = None
    if ws is not None:
        log("translator: adopted prewarmed upstream")
        return ws
    return await _open_upstream()


async def _translator_handler(client_ws):
    """Bridge one hyprwhspr converse client to a persistent omni-realtime upstream."""
    conn = {"ws": None}
    reconnect_lock = asyncio.Lock()
    # Per-utterance counters; reset on input_audio_buffer.clear (recording start).
    state = {"frames": 0, "abytes": 0, "commit_t": None}
    stop = asyncio.Event()

    try:
        conn["ws"] = await _acquire_upstream()
    except Exception as e:
        # Cannot serve: close the client so hyprwhspr fails the dictation within
        # its realtime_timeout rather than hanging.
        log(f"translator: upstream unavailable, closing client ({e})")
        try:
            await client_ws.close(code=1011)
        except Exception:
            pass
        return
    log("translator: upstream session established")

    async def reconnect(old):
        async with reconnect_lock:
            if conn["ws"] is not old:
                return  # another path already reconnected
            try:
                await old.close()
            except Exception:
                pass
            conn["ws"] = await _open_upstream()
            log("translator: upstream reconnected; session re-sent")

    async def client_to_upstream():
        try:
            async for raw in client_ws:
                try:
                    msg = json.loads(raw)
                except (TypeError, ValueError):
                    continue
                t = msg.get("type", "")
                if t == "session.update":
                    # Translator owns the upstream (flat) session config; drop
                    # hyprwhspr's nested realtime session.update.
                    continue
                if t == "response.create":
                    # Instructions are already set at session level; force text.
                    msg = {
                        "type": "response.create",
                        "response": {"modalities": ["text"]},
                    }
                elif t == "input_audio_buffer.append":
                    state["frames"] += 1
                    audio = msg.get("audio") or ""
                    state["abytes"] += (len(audio) * 3) // 4
                elif t == "input_audio_buffer.commit":
                    state["commit_t"] = time.perf_counter()
                elif t == "input_audio_buffer.clear":
                    state["frames"] = 0
                    state["abytes"] = 0
                    state["commit_t"] = None
                payload = json.dumps(msg)
                try:
                    await conn["ws"].send(payload)
                except websockets.exceptions.ConnectionClosed:
                    await reconnect(conn["ws"])
                    await conn["ws"].send(payload)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            stop.set()

    async def upstream_to_client():
        while not stop.is_set():
            ws = conn["ws"]
            try:
                async for raw in ws:
                    try:
                        ev = json.loads(raw)
                    except (TypeError, ValueError):
                        continue
                    t = ev.get("type", "")
                    # hyprwhspr's converse reader must see only the cleaned text:
                    # swallow raw ASR transcription events and any audio output.
                    if t.startswith("response.audio"):
                        continue
                    if t.startswith("conversation.item.input_audio_transcription"):
                        continue
                    if t == "response.text.delta":
                        ev = {
                            "type": "response.output_text.delta",
                            "delta": ev.get("delta", ""),
                        }
                    elif t == "response.text.done":
                        ev = {
                            "type": "response.output_text.done",
                            "text": ev.get("text", ""),
                        }
                    elif t == "response.done":
                        commit_t = state.get("commit_t")
                        ms = (
                            (time.perf_counter() - commit_t) * 1000
                            if commit_t
                            else -1.0
                        )
                        log(
                            "translator: utterance done "
                            f"frames={state['frames']} bytes={state['abytes']} "
                            f"commit->final={ms:.0f}ms"
                        )
                        state["commit_t"] = None
                    try:
                        await client_ws.send(json.dumps(ev))
                    except websockets.exceptions.ConnectionClosed:
                        stop.set()
                        return
            except websockets.exceptions.ConnectionClosed:
                pass
            if stop.is_set():
                break
            # Upstream dropped mid-session (not a client stop): reconnect so the
            # persistent session survives, then resume reading.
            try:
                await reconnect(ws)
            except Exception as e:
                log(f"translator: upstream reconnect failed, closing client ({e})")
                stop.set()
                try:
                    await client_ws.close(code=1011)
                except Exception:
                    pass
                break

    reader = asyncio.create_task(upstream_to_client())
    try:
        # Completes when the hyprwhspr client disconnects (or an unrecoverable
        # upstream failure closes it), ending the persistent session.
        await client_to_upstream()
    finally:
        stop.set()
        reader.cancel()
        try:
            await reader
        except asyncio.CancelledError:
            pass
        try:
            await conn["ws"].close()
        except Exception:
            pass
        log("translator: upstream session closed")


def _translator_prewarm():
    """Schedule a best-effort warm upstream from the sync /prewarm handler."""
    loop = _TRANSLATOR_LOOP
    if loop is None:
        return
    try:
        asyncio.run_coroutine_threadsafe(_warm_upstream_slot(), loop)
    except Exception as e:
        log(f"translator prewarm schedule failed (ignored): {e}")


def translator_thread():
    """Run the loopback translator server in a private asyncio event loop."""

    async def _serve():
        global _TRANSLATOR_LOOP, _WARM_LOCK
        _WARM_LOCK = asyncio.Lock()
        _TRANSLATOR_LOOP = asyncio.get_running_loop()
        async with websockets.serve(
            _translator_handler, BIND_HOST, QWEN_TRANSLATOR_PORT, max_size=None
        ):
            log(
                f"omni-realtime translator listening on "
                f"ws://{BIND_HOST}:{QWEN_TRANSLATOR_PORT} "
                f"(upstream={QWEN_OMNI_REALTIME_WS_URL})"
            )
            await asyncio.Future()  # run forever

    try:
        asyncio.run(_serve())
    except Exception as e:
        log(f"translator thread crashed: {e}")


# --------------------------------------------------------------------------
# HTTP server
# --------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "QwenASRShim/1.0"

    def log_message(self, fmt, *args):
        # Silence default per-request stderr logging; we log our own summary.
        pass

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_text(self, status, text):
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle_cleanup(self):
        """Clean up a raw transcript via chat/completions over the warm pool.

        Reads the raw transcript as the request body (text/plain), runs the
        same cleanup instruction used by handle_transcribe_ws, and returns the
        cleaned text. On any failure returns HTTP 500 so the caller's
        ``curl -sf`` exits non-zero and hyprwhspr falls back to the raw text.
        """
        start = time.perf_counter()
        timings = {}
        try:
            content_length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(content_length) if content_length else b""
            text = raw.decode("utf-8", errors="replace").strip()

            if not text:
                # Nothing to clean; return it unchanged.
                self._send_text(200, text)
                return

            api_key = get_api_key()
            messages = [
                {"role": "system", "content": build_cleanup_instruction("")},
                {"role": "user", "content": text},
            ]
            timeout = min(3.0 + len(text) / 200.0, 10.0)
            t0 = time.perf_counter()
            cleaned, reused, usage = chat_completion(
                QWEN_CLEANUP_MODEL,
                messages,
                api_key,
                extra={"temperature": 0, "enable_thinking": False},
                timeout=timeout,
            )
            timings["cleanup"] = (time.perf_counter() - t0) * 1000
            timings["reused_conn"] = reused

            cleaned = (cleaned or "").strip()
            if not cleaned:
                raise RuntimeError(f"empty cleanup from {QWEN_CLEANUP_MODEL}")

            _record_usage(timings, usage, cleaned)
            self._send_text(200, cleaned)
            timings["total"] = (time.perf_counter() - start) * 1000
            log(format_timing("/cleanup", timings))
        except Exception as e:
            elapsed_ms = (time.perf_counter() - start) * 1000
            message = str(e)
            log(f"POST /cleanup 500 {elapsed_ms:.0f}ms model={QWEN_CLEANUP_MODEL} error={message[:200]}")
            try:
                self._send_json(500, {"error": message})
            except Exception:
                pass

    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
        else:
            self._send_json(404, {"error": f"unknown route {self.path}"})

    def do_POST(self):
        if self.path == "/prewarm":
            # Fire-and-forget: warm the pool without blocking the caller, and
            # (best-effort) pre-establish a warm omni-realtime upstream in the
            # translator so a qwen-omni-realtime record-start finds it ready.
            threading.Thread(target=_background_warm, daemon=True).start()
            _translator_prewarm()
            self.send_response(204)
            self.end_headers()
            return

        if self.path == "/cleanup":
            self._handle_cleanup()
            return

        start = time.perf_counter()
        route = self.path
        model_used = None
        timings = {}
        try:
            if route not in ROUTE_HANDLERS:
                self._send_json(404, {"error": f"unknown route {route}"})
                return

            model_used, handler = ROUTE_HANDLERS[route]

            content_length = int(self.headers.get("Content-Length", "0") or "0")
            body = self.rfile.read(content_length) if content_length else b""
            boundary = get_multipart_boundary(self.headers.get("Content-Type", ""))
            fields = parse_multipart(body, boundary)

            if "file" not in fields:
                raise ValueError("missing 'file' field in multipart/form-data body")
            audio_bytes = fields["file"]["data"]
            prompt = fields.get("prompt", {}).get("data", b"")
            if isinstance(prompt, bytes):
                prompt = prompt.decode("utf-8", errors="replace")
            prompt = prompt.strip()

            api_key = get_api_key()
            text = handler(audio_bytes, prompt, api_key, timings)

            if not text or not text.strip():
                elapsed_ms = (time.perf_counter() - start) * 1000
                log(f"POST {route} 500 {elapsed_ms:.0f}ms model={model_used} error=empty transcription")
                self._send_json(500, {"error": f"empty transcription from {model_used}"})
                return

            self._send_json(200, {"text": text})
            timings["total"] = (time.perf_counter() - start) * 1000
            log(format_timing(route, timings))
        except Exception as e:
            elapsed_ms = (time.perf_counter() - start) * 1000
            message = str(e)
            log(f"POST {route} 500 {elapsed_ms:.0f}ms model={model_used} error={message[:200]}")
            try:
                self._send_json(500, {"error": message})
            except Exception:
                pass


def _background_warm():
    try:
        reused = warm_pool()
        log(f"prewarm ok (reused_conn={reused})")
    except Exception as e:
        log(f"prewarm failed (ignored): {e}")


def main():
    if QWEN_KEEPALIVE_SECONDS > 0:
        threading.Thread(target=keepalive_loop, daemon=True).start()

    # Loopback omni-realtime translator for the qwen-omni-realtime profile.
    threading.Thread(target=translator_thread, daemon=True).start()

    server = ThreadingHTTPServer((BIND_HOST, QWEN_ASR_PORT), Handler)
    log(
        f"listening on {BIND_HOST}:{QWEN_ASR_PORT} "
        f"(chat_url={CHAT_COMPLETIONS_URL} ws_url={REALTIME_WS_URL} "
        f"keepalive={QWEN_KEEPALIVE_SECONDS}s trim_silence={int(QWEN_TRIM_SILENCE)})"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
