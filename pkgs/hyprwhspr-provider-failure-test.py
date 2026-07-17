#!/usr/bin/env python3
"""Behavior checks for the realtime backend and redacted provider failures."""

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
whisper_manager_module = importlib.import_module("whisper_manager")
np = whisper_manager_module.np
requests = whisper_manager_module.requests


# Inline REST configuration kept solely to exercise the package's REST
# log-redaction patches (substituteInPlace in hyprwhspr.nix); the deployed
# static config uses the realtime-ws backend only.
REST_CONFIG = {
    "transcription_backend": "rest-api",
    "rest_api_provider": "openrouter",
    "rest_endpoint_url": "https://openrouter.ai/api/v1/audio/transcriptions",
    "rest_body": {"model": "openai/gpt-4o-mini-transcribe"},
    "rest_timeout": 60,
    "rest_audio_format": "wav",
    "post_transcription_hook": None,
    "whisper_prompt": "",
}


class Config:
    def __init__(self, profile: dict[str, object]):
        self.profile = profile

    def get_setting(self, key: str, default=None):
        return self.profile.get(key, default)

    def get_temp_directory(self) -> Path:
        return Path(tempfile.gettempdir())


class AudioCapture:
    sample_rate = 16_000


class AudioManager:
    def __init__(self):
        self.error_count = 0

    def play_error_sound(self):
        self.error_count += 1


class Response:
    status_code = 401
    text = "provider-response-secret"
    headers = {"Content-Type": "provider-metadata-secret"}

    def json(self):
        return {"error": "provider-json-secret"}


class SuccessResponse:
    status_code = 200
    text = '{"text":"fresh success"}'
    headers = {"Content-Type": "application/json"}

    def json(self):
        return {"text": "fresh success"}


class FakeRealtimeClient:
    def __init__(self, connected: bool = True, result: str | None = None, error: Exception | None = None):
        self.connected = connected
        self.result = result
        self.error = error
        self.commits = 0

    def update_language(self, _language):
        raise AssertionError("no language override configured; update_language must not run")

    def commit_and_get_text(self, timeout=None):
        self.commits += 1
        assert timeout == 30, f"realtime_timeout not honored: {timeout}"
        if self.error is not None:
            raise self.error
        return self.result or ""


def make_app(profile: dict[str, object]):
    manager = whisper_manager_module.WhisperManager(Config(profile))
    manager.ready = True
    manager._numpy_to_wav_bytes = lambda _audio, _rate: b"wav-audio-secret"

    app = main.hyprwhsprApp.__new__(main.hyprwhsprApp)
    app.is_processing = False
    app.current_transcription = ""
    app._current_language_override = None
    app.whisper_manager = manager
    app.audio_capture = AudioCapture()
    app.audio_manager = AudioManager()
    app.injected = []
    app.results = []
    app._inject_text = app.injected.append
    app._notify_capture_subscriber = lambda *_args, **_kwargs: None
    app._clear_mic_osd_preview_text = lambda: None
    app._show_result_and_hide = app.results.append
    return app


def assert_redacted(log: str, forbidden: list[str]):
    for value in forbidden:
        assert value not in log, f"sensitive provider value leaked: {value}"


def load_static_config() -> dict[str, object]:
    config = json.loads(CONFIG.read_text())
    assert config["transcription_backend"] == "realtime-ws"
    assert config["websocket_provider"] == "openai"
    assert config["websocket_model"] == "gpt-4o-transcribe"
    assert config["realtime_mode"] == "transcribe"
    assert config["realtime_timeout"] == 30
    assert config["post_transcription_hook"] is None
    assert "never translate" in config["whisper_prompt"]
    assert config["notification_timeout_ms"] == 0
    assert "realtime_transcription_delay" not in config
    assert not any(key.startswith("rest_") for key in config), (
        "static config must not carry REST settings"
    )
    return config


def run_rest_redaction_case(failure: str):
    profile = REST_CONFIG

    calls = []

    def post(endpoint, *, files, data, headers, timeout):
        calls.append((endpoint, files, data, headers, timeout))
        if failure == "timeout":
            raise requests.exceptions.Timeout(
                "exception-secret https://secret.invalid request-body-secret"
            )
        return Response()

    original_post = requests.post
    original_credential = whisper_manager_module.get_credential
    requests.post = post
    whisper_manager_module.get_credential = lambda _provider: "credential-secret"
    app = make_app(profile)
    audio = np.full(1_600, 0.1, dtype=np.float32)
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            app._process_audio(audio)
    finally:
        requests.post = original_post
        whisper_manager_module.get_credential = original_credential

    log = output.getvalue()
    assert len(calls) == 1
    endpoint, files, data, headers, _timeout = calls[0]
    assert endpoint == profile["rest_endpoint_url"]
    assert data["model"] == profile["rest_body"]["model"]
    assert files["file"][1] == b"wav-audio-secret"
    assert headers["Authorization"] == "Bearer credential-secret"
    assert app.injected == []
    assert app.current_transcription == ""
    assert app.audio_manager.error_count == 1
    assert app.results == [False]
    assert app.is_processing is False
    assert "ERROR: REST API" in log
    assert "[WARN] No transcription generated" in log
    assert_redacted(
        log,
        [
            profile["rest_endpoint_url"],
            profile["rest_body"]["model"],
            "credential-secret",
            "wav-audio-secret",
            "provider-response-secret",
            "provider-json-secret",
            "provider-metadata-secret",
            "exception-secret",
        ],
    )


def run_realtime_startup_rejection():
    """Startup must fail terminally, without a client, when the openai key is absent."""
    config = load_static_config()
    manager = whisper_manager_module.WhisperManager(Config(config))
    original_credential = whisper_manager_module.get_credential
    whisper_manager_module.get_credential = lambda _provider: None
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            initialized = manager.initialize()
    finally:
        whisper_manager_module.get_credential = original_credential
    log = output.getvalue()
    assert initialized is False
    assert manager.ready is False
    assert manager._realtime_client is None
    assert "API key not found in credential store" in log
    assert_redacted(log, ["credential-secret", "wav-audio-secret", "exception-secret"])


def run_realtime_case(failure: str):
    config = load_static_config()

    def forbidden_post(*_args, **_kwargs):
        raise AssertionError("realtime backend must not fall back to REST")

    original_post = requests.post
    original_credential = whisper_manager_module.get_credential
    requests.post = forbidden_post
    whisper_manager_module.get_credential = lambda _provider: "credential-secret"
    app = make_app(config)
    if failure == "disconnected":
        client = FakeRealtimeClient(connected=False)
    else:
        client = FakeRealtimeClient(error=RuntimeError("simulated websocket commit failure"))
    app.whisper_manager._realtime_client = client
    audio = np.full(1_600, 0.1, dtype=np.float32)
    output = io.StringIO()
    try:
        with contextlib.redirect_stdout(output):
            app._process_audio(audio)
    finally:
        requests.post = original_post
        whisper_manager_module.get_credential = original_credential

    log = output.getvalue()
    if failure == "disconnected":
        assert client.commits == 0
        assert "[REALTIME] Client not connected" in log
    else:
        assert client.commits == 1
        assert "[REALTIME] Transcription failed" in log
    assert app.injected == []
    assert app.current_transcription == ""
    assert app.audio_manager.error_count == 1
    assert app.results == [False]
    assert app.is_processing is False
    assert "[WARN] No transcription generated" in log
    assert_redacted(log, ["credential-secret", "wav-audio-secret", "exception-secret"])

    app.whisper_manager._realtime_client = FakeRealtimeClient(result="fresh success")
    requests.post = forbidden_post
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            app._process_audio(audio)
    finally:
        requests.post = original_post

    assert app.injected == ["fresh success"]
    assert app.results == [False, True]
    assert app.is_processing is False


for failure_kind in ("timeout", "http-error"):
    run_rest_redaction_case(failure_kind)

run_realtime_startup_rejection()
for failure_kind in ("disconnected", "commit-error"):
    run_realtime_case(failure_kind)

print("hyprwhspr provider-failure tests passed")
