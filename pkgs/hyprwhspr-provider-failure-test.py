#!/usr/bin/env python3
"""Behavior checks for terminal, redacted REST transcription failures."""

from __future__ import annotations

import contextlib
import importlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


APPDIR = Path(os.environ["HYPRWHSPR_APPDIR"])
SELECTOR = Path(os.environ["HYPRWHISPR_SELECTOR"])
PROFILES = Path(os.environ["HYPRWHISPR_PROFILES"])

sys.path[:0] = [str(APPDIR / "lib"), str(APPDIR / "lib" / "src")]

main = importlib.import_module("main")
whisper_manager_module = importlib.import_module("whisper_manager")
np = whisper_manager_module.np
requests = whisper_manager_module.requests


class Config:
    def __init__(self, profile: dict[str, object]):
        self.profile = profile

    def get_setting(self, key: str, default=None):
        return self.profile.get(key, default)


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


def status(env: dict[str, str]) -> str:
    result = subprocess.run(
        [SELECTOR, "status"],
        capture_output=True,
        text=True,
        env=env,
    )
    if result.returncode != 0:
        safe_stderr = result.stderr.strip()
        for name in (
            "HYPRWHISPR_PROFILE_PROFILES_DIR",
            "HYPRWHISPR_PROFILE_STATE_HOME",
            "HYPRWHISPR_PROFILE_RUNTIME_DIR",
        ):
            safe_stderr = safe_stderr.replace(env[name], f"<{name.lower()}>")
        raise AssertionError(
            f"hyprwhispr-profile status exited {result.returncode}: {safe_stderr}"
        )
    return result.stdout.strip()


def assert_redacted(log: str, profile: dict[str, object]):
    forbidden = [
        profile["rest_endpoint_url"],
        profile["rest_body"]["model"],
        "credential-secret",
        "wav-audio-secret",
        "provider-response-secret",
        "provider-json-secret",
        "provider-metadata-secret",
        "exception-secret",
    ]
    for value in forbidden:
        assert value not in log, f"sensitive REST value leaked: {value}"


def run_case(mode: str, failure: str):
    profile_path = PROFILES / f"{mode}.json"
    profile = json.loads(profile_path.read_text())

    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        state_home = root / "state"
        runtime_dir = root / "runtime"
        mode_dir = state_home / "hyprwhispr-profile"
        mode_dir.mkdir(parents=True)
        runtime_dir.mkdir()
        (mode_dir / "mode").write_text(f"{mode}\n")
        activation = runtime_dir / "config.json"
        activation.symlink_to(profile_path)

        env = os.environ.copy()
        env.update(
            {
                "HYPRWHISPR_PROFILE_PROFILES_DIR": str(PROFILES),
                "HYPRWHISPR_PROFILE_STATE_HOME": str(state_home),
                "HYPRWHISPR_PROFILE_RUNTIME_DIR": str(runtime_dir),
            }
        )
        before_files = sorted(str(path.relative_to(root)) for path in root.rglob("*"))
        before_target = activation.resolve()
        assert status(env) == mode

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
        assert data["model"] == f"openai/gpt-{mode}-transcribe"
        assert files["file"][1] == b"wav-audio-secret"
        assert headers["Authorization"] == "Bearer credential-secret"
        assert app.injected == []
        assert app.current_transcription == ""
        assert app.audio_manager.error_count == 1
        assert app.results == [False]
        assert app.is_processing is False
        assert "ERROR: REST API" in log
        assert "[WARN] No transcription generated" in log
        assert_redacted(log, profile)

        assert status(env) == mode
        assert (mode_dir / "mode").read_text() == f"{mode}\n"
        assert activation.is_symlink()
        assert activation.resolve() == before_target
        assert sorted(str(path.relative_to(root)) for path in root.rglob("*")) == before_files

        success_calls = []

        def successful_post(endpoint, **kwargs):
            success_calls.append((endpoint, kwargs))
            return SuccessResponse()

        requests.post = successful_post
        whisper_manager_module.get_credential = lambda _provider: "credential-secret"
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                app._process_audio(audio)
        finally:
            requests.post = original_post
            whisper_manager_module.get_credential = original_credential

        assert len(success_calls) == 1
        assert success_calls[0][1]["data"]["model"] == profile["rest_body"]["model"]
        assert app.injected == ["fresh success"]
        assert app.results == [False, True]
        assert app.is_processing is False
        assert status(env) == mode


for selected_mode in ("4o", "4o-mini"):
    for failure_kind in ("timeout", "http-error"):
        run_case(selected_mode, failure_kind)

print("hyprwhspr provider-failure tests passed")
