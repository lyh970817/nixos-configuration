#!/usr/bin/env python3
"""Behavior checks for terminal, redacted provider transcription failures."""

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
from unittest import mock


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


def assert_redacted(log: str, forbidden: list[str]):
    for value in forbidden:
        assert value not in log, f"sensitive provider value leaked: {value}"


@contextlib.contextmanager
def isolated_profile_env(mode: str, profile_path: Path):
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        state_home = root / "state"
        runtime_dir = root / "runtime"
        isolated_home = root / "home"
        isolated_config = root / "config"
        isolated_cache = root / "cache"
        isolated_data = root / "data"
        isolated_tmp = root / "tmp"
        mode_dir = state_home / "hyprwhispr-profile"
        mode_dir.mkdir(parents=True)
        runtime_dir.mkdir()
        for directory in (
            isolated_home,
            isolated_config,
            isolated_cache,
            isolated_data,
            isolated_tmp,
        ):
            directory.mkdir()
        (mode_dir / "mode").write_text(f"{mode}\n")
        activation = runtime_dir / "config.json"
        activation.symlink_to(profile_path)

        env = os.environ.copy()
        env.update(
            {
                "HYPRWHISPR_PROFILE_PROFILES_DIR": str(PROFILES),
                "HYPRWHISPR_PROFILE_STATE_HOME": str(state_home),
                "HYPRWHISPR_PROFILE_RUNTIME_DIR": str(runtime_dir),
                "HOME": str(isolated_home),
                "XDG_CONFIG_HOME": str(isolated_config),
                "XDG_CACHE_HOME": str(isolated_cache),
                "XDG_DATA_HOME": str(isolated_data),
                "XDG_STATE_HOME": str(state_home),
                "XDG_RUNTIME_DIR": str(runtime_dir),
                "TMPDIR": str(isolated_tmp),
            }
        )
        yield root, env, activation, mode_dir


def assert_profile_state_intact(
    root: Path,
    activation: Path,
    mode_dir: Path,
    mode: str,
    before_files: list[str],
    before_target: Path,
):
    assert (mode_dir / "mode").read_text() == f"{mode}\n"
    assert activation.is_symlink()
    assert activation.resolve() == before_target
    after_files = sorted(str(path.relative_to(root)) for path in root.rglob("*"))
    assert after_files == before_files, (
        "failed transcription changed isolated profile tree; "
        f"added={sorted(set(after_files) - set(before_files))}, "
        f"removed={sorted(set(before_files) - set(after_files))}"
    )


def run_rest_case(mode: str, failure: str):
    profile_path = PROFILES / f"{mode}.json"
    profile = json.loads(profile_path.read_text())

    with isolated_profile_env(mode, profile_path) as (root, env, activation, mode_dir):
        assert status(env) == mode
        before_files = sorted(str(path.relative_to(root)) for path in root.rglob("*"))
        before_target = activation.resolve()

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
            with mock.patch.dict(os.environ, env, clear=False), contextlib.redirect_stdout(output):
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

        assert_profile_state_intact(root, activation, mode_dir, mode, before_files, before_target)
        assert status(env) == mode

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


def load_realtime_profile() -> dict[str, object]:
    profile = json.loads((PROFILES / "realtime.json").read_text())
    assert profile["transcription_backend"] == "realtime-ws"
    assert profile["websocket_provider"] == "openai"
    assert profile["websocket_model"] == "gpt-4o-mini-transcribe"
    assert profile["realtime_mode"] == "transcribe"
    assert profile["realtime_timeout"] == 30
    assert "realtime_transcription_delay" not in profile
    assert not any(key.startswith("rest_") for key in profile), (
        "realtime profile must not carry REST settings"
    )
    return profile


def run_realtime_startup_rejection():
    """Startup must fail terminally, without a client, when the openai key is absent."""
    profile = load_realtime_profile()
    manager = whisper_manager_module.WhisperManager(Config(profile))
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
    profile_path = PROFILES / "realtime.json"
    profile = load_realtime_profile()
    mode = "realtime"

    with isolated_profile_env(mode, profile_path) as (root, env, activation, mode_dir):
        assert status(env) == mode
        before_files = sorted(str(path.relative_to(root)) for path in root.rglob("*"))
        before_target = activation.resolve()

        def forbidden_post(*_args, **_kwargs):
            raise AssertionError("realtime backend must not fall back to REST")

        original_post = requests.post
        original_credential = whisper_manager_module.get_credential
        requests.post = forbidden_post
        whisper_manager_module.get_credential = lambda _provider: "credential-secret"
        app = make_app(profile)
        if failure == "disconnected":
            client = FakeRealtimeClient(connected=False)
        else:
            client = FakeRealtimeClient(error=RuntimeError("simulated websocket commit failure"))
        app.whisper_manager._realtime_client = client
        audio = np.full(1_600, 0.1, dtype=np.float32)
        output = io.StringIO()
        try:
            with mock.patch.dict(os.environ, env, clear=False), contextlib.redirect_stdout(output):
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

        assert_profile_state_intact(root, activation, mode_dir, mode, before_files, before_target)
        assert status(env) == mode

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
        assert status(env) == mode


for failure_kind in ("timeout", "http-error"):
    run_rest_case("4o-mini", failure_kind)

run_realtime_startup_rejection()
for failure_kind in ("disconnected", "commit-error"):
    run_realtime_case(failure_kind)

print("hyprwhspr provider-failure tests passed")
