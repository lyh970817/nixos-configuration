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

## Stage 4: model, prompt, keybind, and status-indicator tuning

- **Model**: `websocket_model` is now `gpt-4o-transcribe`. The mini model
  produced word-level misrecognitions in practice, and the full model also
  follows prompt instructions more reliably. Latency stays acceptable
  because audio still streams during recording.
- **Cleanup prompt**: `whisper_prompt` (folded by hyprwhspr into the
  realtime session's transcription prompt) asks for polished written
  prose, strict EN/ZH code-switch preservation without translation,
  resolved self-corrections, and merged well-punctuated sentences.
  `language` stays unset — the speaker mixes English and Chinese, and
  forcing one language causes translation drift. Filler removal is
  deliberately NOT instructed: gpt-4o-transcribe drops hesitation fillers
  by default, and instructing what the model already does is redundant.
  Caveats: an ASR prompt is guidance, not commands — aggressive
  restructuring may be applied only partially, and a post-transcription
  LLM hook remains the documented path if prompt-level cleanup proves
  insufficient. Known bug to watch: on (near-)silent input the model may
  echo prompt-like text into the transcript.
- **Escalation variant** (add only if fillers actually appear in output;
  enumerating fillers has a documented priming risk on whisper-1 and is
  unproven on the 4o family): add the sentence "Omit hesitation sounds
  and discourse fillers (um, uh, you know; 嗯, 那个, 就是 when used only
  as fillers)." — or swap the whole prompt for: "Output style: clean,
  edited written text with full punctuation and capitalization — no
  hesitation sounds, no discourse fillers, no false starts or repeated
  words; self-corrections resolved to the speaker's final intent. The
  speaker code-switches between English and Chinese: transcribe each word
  in its original language, never translate. Preserve the meaning
  exactly; do not add, answer, or summarize anything; never repeat these
  instructions in the transcript."
- **Keybind**: dictation toggle moved from `Ctrl+Shift+O` to `Super+O`
  (hyprland bind and `primary_shortcut` kept in sync).
- **Mic OSD**: the GTK4 layer-shell overlay never started on NixOS — the
  package lacked gtk4/gtk4-layer-shell typelibs and GI wiring, and
  upstream's LD_PRELOAD detection only globs /usr/lib*. The package now
  wraps the daemon with GI_TYPELIB_PATH/LD_LIBRARY_PATH/XDG_DATA_DIRS and
  patches the store path into the preload search, so the overlay shows
  while recording and keeps a "transcribing" state from stop until the
  text is injected.
- **Notification fallback**: the non-overlay notification presenter kept
  expiring mid-transcription (mako honors the 5s timeout). The config now
  sets `notification_timeout_ms: 0` (an upstream setting wired into the
  presenter), making recording/processing bubbles persist until replaced
  or closed; success/error remain transient.

## Stage 5: notifications by preference, English-only prompt, commit-race fix

- **Mic OSD reverted by preference**: the GTK4 layer-shell overlay from
  stage 4 worked but the user prefers plain mako notifications, so the
  GTK wiring was reverted and status indication is the persistent
  notification presenter again (`notification_timeout_ms: 0` kept:
  recording/transcribing bubbles persist until replaced or closed).
  Note: `mic_osd_enabled` must stay unset/true — upstream gates the
  ENTIRE status-indicator block (the notification fallback included)
  behind it, so setting it false would remove all indication; with the
  GTK libraries absent the daemon routes to notifications on its own
  ("layer-shell not supported" fallback), and the install check guards
  the key against being set to false.
- **Prompt is now English-only with filler enumeration**: the EN/ZH
  code-switch instruction primed Chinese output into English-only
  dictation (real observed failure) and was removed; explicit filler
  removal (um, uh, you know, like) was added back because the model's
  default filler handling proved insufficient. If restructuring quality
  remains insufficient, the documented next step is a post-transcription
  LLM hook. If dictation goes permanently English-only, setting
  `language: "en"` is a further accuracy win.
- **Empty-commit race fixed**: every stop logged
  `[REALTIME] Server error: Error committing input audio buffer: buffer
  too small ... 0.00ms`. Root cause: `commit_and_get_text` snapshots the
  VAD-committed flag before its queue-drain wait, while the server VAD's
  auto-commit (the "first commit") typically lands during that wait, so
  the client then sent a redundant manual commit against the flushed
  buffer. The package patch (`hyprwhspr-realtime-fixes.patch`, renamed
  from the connect-wait patch) re-checks the flag after the drain, and
  downgrades the residual "buffer too small" server error to a benign
  log line that no longer wakes the transcript waiter early. The
  downgrade is conditional on a prior VAD commit: without one the error
  is genuine (recording too short or silent) and still unblocks the
  waiter immediately, so empty recordings fail fast with "no
  transcription" instead of hanging for the 30s realtime timeout.
- **Cancel no longer wedges the backend**: cancelling a dictation
  (Super+Escape) destroys the realtime client and upstream never
  recreated it, failing every later recording until a daemon restart;
  the package patch now rebuilds the client from the stored connect
  parameters on the next record press.
