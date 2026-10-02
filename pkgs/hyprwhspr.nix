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
      jsonschema
      numpy
      psutil
      pulsectl
      pycairo
      pygobject3
      pyperclip
      pyudev
      requests
      rich
      sounddevice
      soundfile
      soxr
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
  version = "1.47.0";

  src = fetchFromGitHub {
    owner = "goodroot";
    repo = "hyprwhspr";
    rev = "v${version}";
    sha256 = "09w4fyi4gcgf8sawr6h2cq55v9cjjr8lfig6r4n97ycvrj79ja64";
  };

  # Local patches (each must apply without fuzz):
  # - nix-launcher: upstream 1.44+ installs "managed releases" -- the launcher
  #   hands off to ~/.local/share/hyprwhspr/launcher when release.json exists,
  #   probes /usr/bin for a 3.11-3.14 CLI Python, and runs the service from
  #   ~/.local/share/hyprwhspr/venv. Pin both interpreters to @python@ (the
  #   pythonEnv below), drop the hand-off, refuse `update` and
  #   `install repair|status` (they would populate ~/.local/share/hyprwhspr/
  #   releases), and report the pinned version instead of reading release.json
  #   or `git describe`.
  # - realtime-sample-rate: upstream 1.47 added `websocket_sample_rate`
  #   (custom provider only), which sets both resampling and the
  #   session.update rate. The patch is now only an alias: when it is unset,
  #   the profiles' older `realtime_sample_rate` key supplies it. Renaming the
  #   key in config/hyprwhspr/profiles/*.json would make this patch removable.
  # - short-audio-archive: realtime short dictation archives the local mic
  #   capture under ~/.local/share/hyprwhspr/short/audio/<UTC timestamp>.wav
  #   and exports HYPRWHSPR_DICTATION_TS for matching downstream artifacts
  #   (now in lib/src/app/recording.py after 1.46's main.py split).
  # - notification-text: status notifications show only the state (e.g.
  #   "● Recording…") as the summary, with a monochrome recording glyph.
  # - paste-notify: after a successful text injection, send a best-effort
  #   loopback UDP datagram (port 8773) with the paste timestamp and the exact
  #   injected text; qwen-asr-shim uses it for paste-complete latency.
  # - rest-redaction: REST backend logs never carry endpoint URLs, request
  #   values, response bodies or exception strings.
  #
  # Retired at the 1.47.0 bump: realtime-reopen (upstreamed in 1.41.0, #229)
  # and filler-punctuation (superseded by 1.42.3's lib/src/filler_filter.py,
  # which fixed this user's report #242 more thoroughly).
  #
  # Upstream changes 1.40.0 -> 1.47.0 that touch this setup:
  # - realtime-ws: `websocket_sample_rate`/`websocket_protocol`/
  #   `websocket_session_format`/`websocket_live_text` for custom servers;
  #   custom endpoints may be keyless; a malformed websocket_url now fails at
  #   start. The converse session.update now carries the shipped English
  #   capitalization prompt (`whisper_prompt_en`, 1.41) as instructions --
  #   harmless here because qwen-asr-shim drops hyprwhspr's session.update.
  # - text: trailing space is `append_trailing_space` ("auto": none after
  #   CJK text), filler filtering rewritten (1.42.3), `clipboard_settle_delay`
  #   (1.46, package default 0.02 s above).
  # - notifications: "Transcribing…" stays until the text lands (timeout 0);
  #   start/stop cues play through pw-play/paplay before ffplay.
  # - CLI: `record copy-last|paste-last|clear-last|release`, `config
  #   validate`, `status --report`, `transcribe FILE`; `uninstall` keeps
  #   settings unless --purge. faster-whisper on CPU now defaults to int8
  #   (unused: no local backend is packaged).
  patches = [
    ./hyprwhspr-nix-launcher.patch
    ./hyprwhspr-realtime-sample-rate.patch
    ./hyprwhspr-short-audio-archive.patch
    ./hyprwhspr-notification-text.patch
    ./hyprwhspr-paste-notify.patch
    ./hyprwhspr-rest-redaction.patch
  ];

  postPatch = ''
    substituteInPlace bin/hyprwhspr bin/meeting-recorder \
      --subst-var-by python "${pythonEnv}/bin/python"
    substituteInPlace lib/cli.py --subst-var-by version "${version}"
  '';

  nativeBuildInputs = [ makeWrapper ];

  # Package the whole upstream runtime tree (bin, config, lib, share, scripts,
  # utils) -- the shipped commands reach across all of it -- under
  # $out/lib/hyprwhspr, a fixed store layout rather than an emulation of the
  # managed one: no release.json, no ~/.local/share/hyprwhspr/{launcher,venv,
  # releases}. The patched bin/hyprwhspr and bin/meeting-recorder run
  # everything (CLI subcommands and the service alike) on pythonEnv, and each
  # is exposed as a wrapper in $out/bin. A tool that lives only under
  # $out/lib/hyprwhspr/bin is unreachable. Upstream docs, contrib files, and
  # license material go to $out/share/doc/hyprwhspr.
  #
  # Both profiles run the realtime-ws backend against the local qwen-asr-shim.
  # Local backends (pywhispercpp, faster-whisper, onnx-asr, ...) work only if
  # their Python dependencies are added to pythonEnv above; `hyprwhspr setup`
  # and `backend` would try to pip-install them into a user venv instead.
  installPhase = ''
    runHook preInstall

    appdir="$out/lib/hyprwhspr"
    docdir="$out/share/doc/hyprwhspr"
    mkdir -p "$appdir" "$out/bin" "$docdir"
    cp -R bin config lib share scripts utils requirements*.txt "$appdir/"
    cp -R README.md LICENSE contrib docs "$docdir/"

    for program in hyprwhspr meeting-recorder; do
      makeWrapper ${bash}/bin/bash "$out/bin/$program" \
        --add-flags "$appdir/bin/$program" \
        --set HYPRWHSPR_ROOT "$appdir" \
        --set PYTHONUNBUFFERED "1" \
        --prefix PATH : "${runtimePath}" \
        --prefix PYTHONPATH : "$appdir/lib:$appdir/lib/src"
    done

    # Nixpkgs ydotoold reports "unknown" for --version; trust the pinned package version.
    substituteInPlace "$appdir/lib/src/cli/_shared.py" \
      --replace-fail '        version = "0.1.0"' '        version = "${ydotool.version}"'

    substituteInPlace "$appdir/lib/src/text_injector.py" \
      --replace-fail 'Env: HYPRWHSPR_MODEL, HYPRWHSPR_BACKEND. 5s timeout.' \
        'Env: HYPRWHSPR_MODEL, HYPRWHSPR_BACKEND. 12s timeout.' \
      --replace-fail 'text=True, timeout=5.0, env=env,' 'text=True, timeout=12.0, env=env,'

    substituteInPlace "$appdir/share/config.schema.json" \
      --replace-fail 'Subject to a 5s timeout; other errors pass through the original text.' \
        'Subject to a 12s timeout; other errors pass through the original text.'

    # Clipboard-to-paste settle time. 1.40.0 hard-coded 0.15 s and this
    # package cut it to 0.02 s; 1.46.0 made it `clipboard_settle_delay`, so
    # keep the package default at 0.02 s (a profile value still wins).
    substituteInPlace "$appdir/lib/src/config_manager.py" \
      --replace-fail "'clipboard_settle_delay': 0.15," "'clipboard_settle_delay': 0.02,"
    substituteInPlace "$appdir/share/config.schema.json" \
      --replace-fail '"default": 0.15,' '"default": 0.02,'

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HYPRWHSPR_APPDIR="$out/lib/hyprwhspr" \
      HYPRWHISPR_CONFIG=${../config/hyprwhspr/profiles/qwen-audio3.json} \
      ${pythonEnv}/bin/python ${./hyprwhspr-provider-failure-test.py}

    # The launcher runs on the store layout and never reaches for the
    # managed-release machinery.
    export HOME="$TMPDIR/home"
    [ "$("$out/bin/hyprwhspr" --version)" = "hyprwhspr v${version}" ]
    if "$out/bin/hyprwhspr" update 2>/dev/null; then
      echo "hyprwhspr update must refuse in the Nix package" >&2
      exit 1
    fi
    [ ! -e "$HOME/.local/share/hyprwhspr" ]
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
