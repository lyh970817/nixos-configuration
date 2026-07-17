# Hyprwhispr realtime streaming — stage 2

## Motivation

The REST profiles upload the whole recording after the user stops talking, so
post-stop latency grows with utterance length: record, stop, upload, wait for
the full transcription round trip. Commercial dictation apps hide this by
streaming audio to the transcription service during recording, so the
transcript is nearly complete at the moment the user stops. hyprwhspr 1.34.1
ships a `realtime-ws` transcription backend that does exactly this over a
websocket.

## Profile pair

- `realtime` — `transcription_backend: "realtime-ws"`, provider `openai`,
  model `gpt-4o-mini-transcribe`, `realtime_mode: "transcribe"`. The websocket
  URL auto-derives to `wss://api.openai.com/v1/realtime`. This is the same
  model as the REST fallback, so accent accuracy is identical — only the
  transport changes: audio streams during recording instead of uploading
  after stop.
- `4o-mini` — unchanged REST profile (`openai/gpt-4o-mini-transcribe` via
  OpenRouter). This is the default profile and the fallback for every
  bad-state recovery path in `scripts/hyprwhispr-profile`, because it works
  with the already-provisioned OpenRouter credential.

`hyprwhispr-profile toggle` switches between the two; `set realtime` /
`set 4o-mini` select one explicitly.

## Credential requirement

The realtime backend looks up its credential by the `websocket_provider`
value, so `secrets/hyprwhspr-credentials.json` (symlinked to
`~/.local/share/hyprwhspr/credentials`, never committed) must gain an
`"openai"` key holding a direct OpenAI API key before `set realtime` will
work. OpenRouter keys cannot be used: OpenRouter has no websocket realtime
endpoint. Until the key is added, stay on the default `4o-mini` profile.

## Startup behavior and failure handling

The websocket handshake takes a few seconds after daemon start. Upstream
1.34.1 destroyed an in-flight handshake when a record press arrived during
it (and a connect timeout could close a socket owned by a concurrent
reconnect attempt); upstream has no fix as of July 2026, so
`pkgs/hyprwhspr-realtime-connect-wait.patch` makes record presses wait up
to 8s for the in-flight connection instead, and connect attempts now only
close sockets they created. The profile selector gives the realtime daemon
a ~30s readiness window (vs ~10s for REST) to cover websocket startup plus
one daemon crash and systemd restart.

Switching to realtime either succeeds or fails loudly: if the daemon does
not become ready, the selector exits non-zero, notifies, and stays on the
realtime profile rather than silently reverting. Recover manually with
`hyprwhispr-profile set 4o-mini`. The boot-time default remains `4o-mini`.

## Alternatives

- `gpt-realtime-whisper` is the documented alternative websocket model. It
  adds a live partial-caption display in the mic OSD and a tunable
  `realtime_transcription_delay` (minimal|low|medium|high|xhigh), but its
  accent accuracy is unproven, so it was not chosen.
- Accuracy escape hatch: if accent accuracy suffers, switch the
  `websocket_model` in the static config to `gpt-4o-transcribe`, which the
  realtime endpoint also serves, at the cost of some streaming latency.

## Stage 3: experiment concluded

The A/B experiment is over: the realtime websocket backend won and is now
the sole backend. The REST profile and the whole selector machinery —
`config/hyprwhspr/profiles/`, `hyprwhispr-profile`, the boot-time ensure
step, and the Ctrl+Shift+P toggle — were removed. The sections above
describing the profile pair are historical; git history holds the full
A/B setup if a REST fallback is ever needed again.

The daemon now reads one static config: `config/hyprwhspr/config.json` in
this repo, installed at `~/.config/hyprwhspr/config.json` and linked into
`$XDG_RUNTIME_DIR/hyprwhspr/config.json` by a service pre-start step (the
daemon keeps `XDG_CONFIG_HOME` on the runtime dir so its mutable state
stays on tmpfs). Startup failures stay loud: the daemon fail-fasts,
systemd restarts it, and the connect-wait patch keeps record presses from
killing an in-flight websocket handshake. The `openai` credential remains
required; `openrouter` is no longer read but may stay in the secrets file
(`custom` is still used by long-form polishing).
