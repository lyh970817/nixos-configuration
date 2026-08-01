#!/usr/bin/env python3
"""Behavior checks for local hyprwhspr packaging and provider redaction."""

from __future__ import annotations

import contextlib
import importlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile


APPDIR = Path(os.environ["HYPRWHSPR_APPDIR"])
CONFIG = Path(os.environ["HYPRWHISPR_CONFIG"])
sys.path[:0] = [str(APPDIR / "lib"), str(APPDIR / "lib" / "src")]

main = importlib.import_module("main")
realtime_client_module = importlib.import_module("realtime_client")
realtime_backend_module = importlib.import_module("backends.realtime_ws_backend")
rest_backend_module = importlib.import_module("backends.rest_api_backend")
np = importlib.import_module("numpy")
requests = rest_backend_module.requests


class Config:
    def __init__(self, values: dict[str, object]):
        self.values = values

    def get_setting(self, key: str, default=None):
        return self.values.get(key, default)

    def migrate_api_key_to_credential_manager(self) -> None:
        pass


class Manager:
    def __init__(self, values: dict[str, object]):
        self.config = Config(values)
        self.temp_dir = None
        self.ready = False
        self.current_model = None
        self._last_use_time = 0
        self._realtime_partial_callback = None


class FakeWebSocket:
    def __init__(self):
        self.sent: list[dict[str, object]] = []

    def send(self, payload: str) -> None:
        self.sent.append(json.loads(payload))


class FakeResponse:
    def __init__(
        self,
        status_code: int = 200,
        payload: object | None = None,
        text: str = "",
        json_error: Exception | None = None,
    ):
        self.status_code = status_code
        self.payload = payload
        self.text = text
        self.json_error = json_error
        self.headers = {"Content-Type": "response-metadata-secret"}

    def json(self):
        if self.json_error is not None:
            raise self.json_error
        return self.payload


def load_profile() -> dict[str, object]:
    profile = json.loads(CONFIG.read_text())
    assert profile["transcription_backend"] == "realtime-ws"
    assert profile["websocket_provider"] == "custom"
    assert profile["websocket_model"] == "qwen-audio-3.0-realtime-plus"
    assert profile["realtime_mode"] == "converse"
    assert profile["realtime_sample_rate"] == 16000
    assert profile["realtime_timeout"] == 8
    return profile


def run_realtime_sample_rate_checks(profile: dict[str, object]) -> None:
    original_credential = realtime_backend_module.get_credential
    original_connect = realtime_client_module.RealtimeClient.connect

    def fake_connect(client, url, api_key, model_id, instructions):
        client.url = url
        client.api_key = api_key
        client.model = model_id
        client.instructions = instructions
        client.connected = True
        return True

    realtime_backend_module.get_credential = lambda _provider: "credential-secret"
    realtime_client_module.RealtimeClient.connect = fake_connect
    try:
        backend = realtime_backend_module.RealtimeWsBackend(Manager(profile))
        assert backend.initialize() is True
    finally:
        realtime_client_module.RealtimeClient.connect = original_connect
        realtime_backend_module.get_credential = original_credential

    client = backend._realtime_client
    assert isinstance(client, realtime_client_module.RealtimeClient)
    assert client.sample_rate == 16000
    assert backend._realtime_connect_params == {
        "websocket_url": profile["websocket_url"],
        "api_key": "credential-secret",
        "model_id": profile["websocket_model"],
        "instructions": None,
    }

    client.ws = FakeWebSocket()
    client._send_session_update()
    audio_format = client.ws.sent[-1]["session"]["audio"]["input"]["format"]
    assert audio_format == {"type": "audio/pcm", "rate": 16000}

    client.set_input_sample_rate(44100)
    resampled = client._resample_for_output(np.zeros(4410, dtype=np.float32))
    assert len(resampled) == 1600
    assert resampled.dtype == np.float32

    schema = json.loads((APPDIR / "share" / "config.schema.json").read_text())
    rate_schema = schema["properties"]["realtime_sample_rate"]
    assert rate_schema == {
        "type": "integer",
        "minimum": 8000,
        "maximum": 48000,
        "default": 24000,
        "description": "PCM sample rate required by the selected realtime provider",
    }


REST_CONFIG = {
    "rest_endpoint_url": "https://endpoint-secret.invalid/v1/audio/transcriptions",
    "rest_api_provider": "openrouter",
    "rest_headers": {"X-Private": "header-secret"},
    "rest_body": {
        "model": "model-secret",
        "prompt": "prompt-secret-that-must-not-be-logged",
    },
    "rest_timeout": 12,
}

FORBIDDEN_LOG_VALUES = [
    "endpoint-secret",
    "credential-secret",
    "header-secret",
    "model-secret",
    "prompt-secret",
    "provider-json-secret",
    "provider-text-secret",
    "response-metadata-secret",
    "exception-secret",
]


def assert_redacted(log: str) -> None:
    for value in FORBIDDEN_LOG_VALUES:
        assert value not in log, f"provider log leaked {value!r}: {log}"


def run_rest_case(post):
    manager = Manager(REST_CONFIG)
    backend = rest_backend_module.RestApiBackend(manager)
    original_credential = rest_backend_module.get_credential
    original_post = rest_backend_module.requests.post
    rest_backend_module.get_credential = lambda _provider: "credential-secret"
    rest_backend_module.requests.post = post
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            assert backend.initialize() is True
            result = backend.transcribe(np.zeros(1600, dtype=np.float32), 16000)
    finally:
        rest_backend_module.requests.post = original_post
        rest_backend_module.get_credential = original_credential
    log = output.getvalue()
    assert_redacted(log)
    return result, log


def run_rest_redaction_checks() -> None:
    calls = []

    def success_post(url, **kwargs):
        calls.append((url, kwargs))
        return FakeResponse(payload={"text": "transcribed"})

    result, log = run_rest_case(success_post)
    assert result == "transcribed"
    assert "[REST API] configured endpoint" in log
    assert "[REST] Audio prepared in memory" in log
    assert "[REST] Request fields: model, prompt" in log
    assert calls[0][0] == REST_CONFIG["rest_endpoint_url"]
    assert calls[0][1]["headers"]["Authorization"] == "Bearer credential-secret"
    assert calls[0][1]["headers"]["X-Private"] == "header-secret"
    assert calls[0][1]["data"] == REST_CONFIG["rest_body"]

    cases = [
        lambda *_args, **_kwargs: FakeResponse(
            status_code=429, payload={"error": "provider-json-secret"}
        ),
        lambda *_args, **_kwargs: FakeResponse(
            status_code=502,
            text="provider-text-secret",
            json_error=ValueError("exception-secret"),
        ),
        lambda *_args, **_kwargs: FakeResponse(
            text="provider-text-secret",
            json_error=ValueError("exception-secret"),
        ),
        lambda *_args, **_kwargs: FakeResponse(
            payload={"unexpected": "provider-json-secret"}
        ),
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            requests.exceptions.Timeout("exception-secret")
        ),
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            requests.exceptions.ConnectionError("exception-secret")
        ),
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            requests.exceptions.RequestException("exception-secret")
        ),
        lambda *_args, **_kwargs: (_ for _ in ()).throw(
            RuntimeError("exception-secret")
        ),
    ]
    for post in cases:
        result, _log = run_rest_case(post)
        assert result == ""


def run_archive_check() -> None:
    class AudioCapture:
        def __init__(self):
            self.path = None

        def save_audio_to_wav(self, audio, path):
            assert len(audio) == 160
            self.path = Path(path)
            self.path.write_bytes(b"wav")

    app = main.hyprwhsprApp.__new__(main.hyprwhsprApp)
    app.audio_capture = AudioCapture()
    original_timestamp = main.time.strftime
    previous_data_home = os.environ.get("XDG_DATA_HOME")
    previous_dictation_ts = os.environ.get("HYPRWHSPR_DICTATION_TS")
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            os.environ["XDG_DATA_HOME"] = temp_dir
            main.time.strftime = lambda *_args, **_kwargs: "20260731T120000Z"
            app._archive_short_dictation_audio(np.zeros(160, dtype=np.float32))
            expected = (
                Path(temp_dir)
                / "hyprwhspr"
                / "short"
                / "audio"
                / "20260731T120000Z.wav"
            )
            assert app.audio_capture.path == expected
            assert expected.read_bytes() == b"wav"
            assert os.environ["HYPRWHSPR_DICTATION_TS"] == "20260731T120000Z"
    finally:
        main.time.strftime = original_timestamp
        if previous_data_home is None:
            os.environ.pop("XDG_DATA_HOME", None)
        else:
            os.environ["XDG_DATA_HOME"] = previous_data_home
        if previous_dictation_ts is None:
            os.environ.pop("HYPRWHSPR_DICTATION_TS", None)
        else:
            os.environ["HYPRWHSPR_DICTATION_TS"] = previous_dictation_ts


def main_check() -> None:
    profile = load_profile()
    run_realtime_sample_rate_checks(profile)
    run_rest_redaction_checks()
    run_archive_check()
    print("hyprwhspr package behavior checks passed")


if __name__ == "__main__":
    main_check()
