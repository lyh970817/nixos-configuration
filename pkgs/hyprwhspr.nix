{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  bash,
  python3,
  coreutils,
  dbus,
  ffmpeg,
  glib,
  gnugrep,
  gnused,
  hyprland,
  libnotify,
  pipewire,
  pulseaudio,
  which,
  wl-clipboard,
  wtype,
  ydotool,
}:

let
  pythonEnv = python3.withPackages (
    ps: with ps; [
      dbus-python
      elevenlabs
      evdev
      numpy
      psutil
      pulsectl
      pycairo
      pygobject3
      pyperclip
      pyudev
      requests
      rich
      scipy
      sounddevice
      websocket-client
    ]
  );

  runtimePath = lib.makeBinPath [
    coreutils
    dbus
    ffmpeg
    glib
    gnugrep
    gnused
    hyprland
    libnotify
    pipewire
    pulseaudio
    which
    wl-clipboard
    wtype
    ydotool
  ];

in
stdenvNoCC.mkDerivation rec {
  pname = "hyprwhspr";
  version = "1.34.1";

  src = fetchFromGitHub {
    owner = "goodroot";
    repo = "hyprwhspr";
    rev = "v${version}";
    sha256 = "0rawmq2lvlkz11pj0fk7xmar52ia2mjrzxnx3i4wpb5pg4h0a9n2";
  };

  # Realtime websocket fixes:
  # - a record press during the handshake used to tear the handshake down and
  #   fail the recording; wait for the in-flight connect instead, and never
  #   close a socket another connect attempt owns;
  # - the stop-time buffer commit raced the server-VAD auto-commit, sending a
  #   redundant commit against an already-flushed buffer; re-check the commit
  #   flag after the drain wait and treat the residual "buffer too small"
  #   server error as benign instead of waking the transcript waiter;
  # - cancelling a dictation destroyed the realtime client and nothing ever
  #   recreated it, wedging the backend until daemon restart; cancel now keeps
  #   the websocket alive (server buffer cleared, in-flight events for the
  #   cancelled utterance discarded until the next recording start), falling
  #   back to the old destroy path on a dead connection, and the client is
  #   rebuilt from the stored connect params on the next record press.
  patches = [ ./hyprwhspr-realtime-fixes.patch ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    appdir="$out/lib/hyprwhspr"
    docdir="$out/share/doc/hyprwhspr"
    mkdir -p "$appdir" "$out/bin" "$docdir"
    cp -R bin config lib share scripts utils requirements.txt requirements-visualizer.txt "$appdir/"
    cp -R README.md LICENSE contrib docs "$docdir/"

    makeWrapper ${bash}/bin/bash "$out/bin/hyprwhspr" \
      --add-flags "$appdir/bin/hyprwhspr" \
      --set HYPRWHSPR_ROOT "$appdir" \
      --set PYTHONUNBUFFERED "1" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$appdir/lib:$appdir/lib/src"

    makeWrapper ${bash}/bin/bash "$out/bin/meeting-recorder" \
      --add-flags "$appdir/bin/meeting-recorder" \
      --set HYPRWHSPR_ROOT "$appdir" \
      --set PYTHONUNBUFFERED "1" \
      --prefix PATH : "${runtimePath}" \
      --prefix PYTHONPATH : "$appdir/lib:$appdir/lib/src"

    substituteInPlace "$appdir/bin/hyprwhspr" \
      --replace-fail 'local system_path="/usr/bin:/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/sbin"' \
        'local system_path="${pythonEnv}/bin"' \
      --replace-fail 'VENV_PYTHON="''${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv/bin/python"' \
        'VENV_PYTHON="${pythonEnv}/bin/python"'

    substituteInPlace "$appdir/bin/meeting-recorder" \
      --replace-fail 'VENV_PYTHON="''${XDG_DATA_HOME:-$HOME/.local/share}/hyprwhspr/venv/bin/python"' \
        'VENV_PYTHON="${pythonEnv}/bin/python"'

    # Nixpkgs ydotoold reports "unknown" for --version; trust the pinned package version.
    substituteInPlace "$appdir/lib/src/cli_commands.py" \
      --replace-fail '        version = "0.1.0"' '        version = "${ydotool.version}"'

    substituteInPlace "$appdir/lib/src/text_injector.py" \
      --replace-fail 'Env: HYPRWHSPR_MODEL, HYPRWHSPR_BACKEND. 5s timeout. Any error' \
        'Env: HYPRWHSPR_MODEL, HYPRWHSPR_BACKEND. 12s timeout. Any error' \
      --replace-fail 'text=True, timeout=5.0, env=env,' 'text=True, timeout=12.0, env=env,'

    # Keep remote failure diagnostics useful without logging request values,
    # endpoint URLs, response bodies, or exception strings.
    substituteInPlace "$appdir/lib/src/whisper_manager.py" \
      --replace-fail "print(f'WARNING: REST endpoint URL should start with https:// or http://: {endpoint_url}')" \
        "print('WARNING: REST endpoint URL must use HTTP or HTTPS')" \
      --replace-fail "print(f'[BACKEND] Using REST API: {endpoint_url}')" \
        "print('[BACKEND] Using configured REST API')" \
      --replace-fail "print(f'WARNING: Skipping non-serializable rest_headers entry: {key}')" \
        "print('WARNING: Skipping invalid REST header entry')" \
      --replace-fail "print(f'WARNING: Skipping rest_body entry with non-stringable key: {key}')" \
        "print('WARNING: Skipping REST body entry with invalid key')" \
      --replace-fail "print(f'WARNING: rest_body values must be scalar (key: {key_str}); skipping entry')" \
        "print('WARNING: Skipping non-scalar REST body entry')" \
      --replace-fail "backend_name = endpoint_url" \
        "backend_name = 'configured endpoint'" \
      --replace-fail "log_msg = f'[REST API] {backend_name} - model: {model_info}'" \
        "log_msg = f'[REST API] {backend_name}'" \
      --replace-fail "f'[REST] Audio: {audio_duration:.2f}s @ {sample_rate}Hz, {len(wav_bytes)} bytes'," \
        "'[REST] Audio prepared in memory'," \
      --replace-fail "param_summary = ', '.join(f'{k}={v[:20] + \"...\" if isinstance(v, str) and len(v) > 20 else v}' for k, v in data.items())" \
        "param_summary = ', '.join(sorted(str(k) for k in data))" \
      --replace-fail "print(f'[REST] Request params: {param_summary}', flush=True)" \
        "print(f'[REST] Request fields: {param_summary}', flush=True)" \
      --replace-fail "print(f'[REST] Sending request to {endpoint_url}...', flush=True)" \
        "print('[REST] Sending transcription request', flush=True)" \
      --replace-fail "error_msg += f': {error_detail}'" \
        "error_msg += ' (provider error details redacted)'" \
      --replace-fail "error_msg += f': {response.text[:200]}'" \
        "error_msg += ' (non-JSON provider error details redacted)'" \
      --replace-fail "print(f'ERROR: Failed to parse JSON response: {json_err}')" \
        "print('ERROR: REST API returned invalid JSON')" \
      --replace-fail "print(f'[REST] Raw response body: {raw_body}')" \
        "print('[REST] Response body redacted')" \
      --replace-fail "print(f'[REST] Content-Type: {response.headers.get(\"Content-Type\", \"not set\")}')" \
        "print('[REST] Response metadata redacted')" \
      --replace-fail "print(f'ERROR: Unexpected response format: {result}')" \
        "print('ERROR: REST API returned an unexpected response schema')" \
      --replace-fail "print(f'ERROR: REST API request timed out after {timeout}s')" \
        "print('ERROR: REST API transcription request timed out')" \
      --replace-fail "print(f'ERROR: Failed to connect to REST API: {e}')" \
        "print('ERROR: REST API connection failed')" \
      --replace-fail "print(f'ERROR: REST API request failed: {e}')" \
        "print('ERROR: REST API transcription request failed')" \
      --replace-fail "print(f'ERROR: REST transcription failed: {e}')" \
        "print('ERROR: REST transcription failed unexpectedly')"

    substituteInPlace "$appdir/share/config.schema.json" \
      --replace-fail 'Subject to a 5s timeout; errors pass through the original text.' \
        'Subject to a 12s timeout; errors pass through the original text.'

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HYPRWHSPR_APPDIR="$out/lib/hyprwhspr" \
      HYPRWHISPR_CONFIG=${../config/hyprwhspr/config.json} \
      ${pythonEnv}/bin/python ${./hyprwhspr-provider-failure-test.py}
    runHook postInstallCheck
  '';

  meta = {
    description = "Native speech-to-text for Linux";
    homepage = "https://github.com/goodroot/hyprwhspr";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "hyprwhspr";
  };
}
