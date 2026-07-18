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
  GET  /health           - liveness check

Intended to run as a small long-lived local service (e.g. under a systemd
user unit, configured elsewhere) fronting hyprwhspr's REST backend.
"""

import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import websocket

DEFAULT_CLEANUP_PROMPT = (
    "You clean up dictated speech transcripts. Remove filler words and false "
    "starts, keep only the final wording of any self-correction, fix "
    "punctuation and capitalization, and correct obvious speech-recognition "
    "errors of technical terms. Output only the cleaned transcript text, "
    "with no preamble, quotes, or commentary."
)


def _env(name, default):
    value = os.environ.get(name)
    return value if value not in (None, "") else default


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
QWEN_ASR_LANGUAGE = _env("QWEN_ASR_LANGUAGE", "en")
QWEN_CLEANUP_PROMPT = _env("QWEN_CLEANUP_PROMPT", DEFAULT_CLEANUP_PROMPT)
QWEN_CHAT_TIMEOUT = float(_env("QWEN_CHAT_TIMEOUT", "25"))
QWEN_WS_TIMEOUT = float(_env("QWEN_WS_TIMEOUT", "25"))

CHAT_COMPLETIONS_URL = f"https://{QWEN_ASR_HOST}/compatible-mode/v1/chat/completions"
REALTIME_WS_URL = f"wss://{QWEN_ASR_HOST}/api-ws/v1/realtime?model={QWEN_WS_MODEL}"

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
# ffmpeg helpers
# --------------------------------------------------------------------------

def _run_ffmpeg(args):
    try:
        return subprocess.run(args, check=True, capture_output=True)
    except FileNotFoundError:
        raise RuntimeError("ffmpeg binary not found on PATH") from None
    except subprocess.CalledProcessError as e:
        stderr = e.stderr.decode("utf-8", errors="replace")[:300] if e.stderr else ""
        raise RuntimeError(f"ffmpeg failed (exit {e.returncode}): {stderr}") from None


def to_wav_16k_mono(input_bytes):
    """Resample arbitrary input audio bytes to a 16kHz mono WAV file's bytes."""
    in_path = tempfile.mktemp(suffix=".in")
    out_path = tempfile.mktemp(suffix=".wav")
    try:
        with open(in_path, "wb") as f:
            f.write(input_bytes)
        _run_ffmpeg(["ffmpeg", "-y", "-i", in_path, "-ar", "16000", "-ac", "1", "-f", "wav", out_path])
        with open(out_path, "rb") as f:
            return f.read()
    finally:
        for p in (in_path, out_path):
            try:
                os.remove(p)
            except OSError:
                pass


def to_pcm_16k_mono(input_bytes):
    """Resample arbitrary input audio bytes to raw 16kHz mono s16le PCM (no WAV header)."""
    in_path = tempfile.mktemp(suffix=".in")
    try:
        with open(in_path, "wb") as f:
            f.write(input_bytes)
        result = _run_ffmpeg(["ffmpeg", "-y", "-i", in_path, "-ar", "16000", "-ac", "1", "-f", "s16le", "-"])
        return result.stdout
    finally:
        try:
            os.remove(in_path)
        except OSError:
            pass


# --------------------------------------------------------------------------
# DashScope chat/completions (HTTP)
# --------------------------------------------------------------------------

def chat_completion(model, messages, api_key, extra=None, timeout=QWEN_CHAT_TIMEOUT):
    body = {"model": model, "messages": messages, "stream": False}
    if extra:
        body.update(extra)
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        CHAT_COMPLETIONS_URL,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"chat/completions HTTP {e.code}: {detail}") from None
    except urllib.error.URLError as e:
        raise RuntimeError(f"chat/completions request failed: {e.reason}") from None

    try:
        return payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(
            f"unexpected chat/completions response shape: {json.dumps(payload)[:300]}"
        ) from None


def build_cleanup_instruction(prompt):
    text = QWEN_CLEANUP_PROMPT
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
            time.sleep(0.3)
            chunk_size = 3200  # 100ms of 16k mono s16le
            for i in range(0, len(pcm), chunk_size):
                ws.send(json.dumps({
                    "type": "input_audio_buffer.append",
                    "audio": base64.b64encode(pcm[i:i + chunk_size]).decode(),
                }))
                time.sleep(0.02)
            ws.send(json.dumps({"type": "input_audio_buffer.commit"}))
            time.sleep(0.2)
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

def handle_transcribe_http(audio_bytes, prompt, api_key):
    wav_bytes = to_wav_16k_mono(audio_bytes)
    b64 = base64.b64encode(wav_bytes).decode()

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
    return chat_completion(QWEN_HTTP_MODEL, messages, api_key)


def handle_transcribe_ws(audio_bytes, prompt, api_key):
    pcm = to_pcm_16k_mono(audio_bytes)
    raw_transcript = transcribe_via_websocket(pcm, api_key)

    messages = [
        {"role": "system", "content": build_cleanup_instruction(prompt)},
        {"role": "user", "content": raw_transcript},
    ]
    return chat_completion(
        QWEN_CLEANUP_MODEL,
        messages,
        api_key,
        extra={"temperature": 0, "enable_thinking": False},
    )


def handle_transcribe_omni(audio_bytes, prompt, api_key):
    wav_bytes = to_wav_16k_mono(audio_bytes)
    b64 = base64.b64encode(wav_bytes).decode()

    messages = [
        {"role": "system", "content": build_cleanup_instruction(prompt)},
        {
            "role": "user",
            "content": [{
                "type": "input_audio",
                "input_audio": {"data": f"data:audio/wav;base64,{b64}", "format": "wav"},
            }],
        },
    ]
    return chat_completion(QWEN_OMNI_MODEL, messages, api_key, extra={"modalities": ["text"]})


ROUTE_HANDLERS = {
    "/transcribe/http": (QWEN_HTTP_MODEL, handle_transcribe_http),
    "/transcribe/ws": (f"{QWEN_WS_MODEL}+{QWEN_CLEANUP_MODEL}", handle_transcribe_ws),
    "/transcribe/omni": (QWEN_OMNI_MODEL, handle_transcribe_omni),
}


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

    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"status": "ok"})
        else:
            self._send_json(404, {"error": f"unknown route {self.path}"})

    def do_POST(self):
        start = time.time()
        route = self.path
        model_used = None
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
            text = handler(audio_bytes, prompt, api_key)

            if not text or not text.strip():
                elapsed_ms = (time.time() - start) * 1000
                log(f"POST {route} 500 {elapsed_ms:.0f}ms model={model_used} error=empty transcription")
                self._send_json(500, {"error": f"empty transcription from {model_used}"})
                return

            self._send_json(200, {"text": text})
            elapsed_ms = (time.time() - start) * 1000
            log(f"POST {route} 200 {elapsed_ms:.0f}ms model={model_used} out_len={len(text)}")
        except Exception as e:
            elapsed_ms = (time.time() - start) * 1000
            message = str(e)
            log(f"POST {route} 500 {elapsed_ms:.0f}ms model={model_used} error={message[:200]}")
            try:
                self._send_json(500, {"error": message})
            except Exception:
                pass


def main():
    server = ThreadingHTTPServer((BIND_HOST, QWEN_ASR_PORT), Handler)
    log(
        f"listening on {BIND_HOST}:{QWEN_ASR_PORT} "
        f"(chat_url={CHAT_COMPLETIONS_URL} ws_url={REALTIME_WS_URL})"
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
