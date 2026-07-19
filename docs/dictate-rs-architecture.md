# dictate-rs Architecture Plan

## Summary

`dictate-rs` is a standalone Rust project that provides a resident dictation daemon for a Hyprland, Alacritty, tmux, and interactive Codex CLI workflow. Codex is an integration target, not the owner of the system.

Repository and binaries:

```text
repo: dictate-rs

binaries:
  dictate             # controller CLI
  dictated            # user-level daemon
  dictate-codex-hook  # Codex UserPromptSubmit hook adapter
```

## Core Workflow

```text
Hyprland hotkey
  -> dictate toggle
  -> dictated resolves focused context
  -> CPAL microphone capture
  -> WebRTC VAD auto-stop
  -> Whisper-compatible transcription endpoint
  -> optional LLM cleanup through Chat Completions or Responses
  -> temporary clipboard paste into active focused app
  -> record insertion session for learning

Codex prompt submit
  -> Codex UserPromptSubmit hook
  -> dictate-codex-hook
  -> dictated observes final submitted prompt
  -> local diff heuristics extract correction candidates
  -> repeated observations promote learned corrections
```

## Primary Design Choices

V1 targets the real local stack first:

```text
OS/session:     NixOS + Hyprland Wayland
terminal:       Alacritty
multiplexer:    tmux
main app:       interactive Codex CLI
audio:          PipeWire system, captured through CPAL
delivery:       Wayland clipboard + ydotool paste
notifications:  Mako through DBus notification API
```

Generic GNOME, KDE, X11, and editor-plugin support is out of scope for v1. The interfaces should still allow later backends.

## Daemon

`dictated` is a user-level systemd service, not a root service.

Responsibilities:

```text
recording state machine
audio capture
VAD auto-stop
transcription calls
LLM post-processing calls
context resolution
clipboard paste delivery
persistent notification lifecycle
session tracking
learning pipeline
config/dictionary loading
```

It listens on a Unix socket:

```text
$XDG_RUNTIME_DIR/dictate/dictated.sock
```

IPC is newline-delimited typed JSON, not formal JSON-RPC:

```json
{"version":1,"id":"...","method":"toggle","params":{"profile":"clean"}}
{"version":1,"id":"...","method":"status","params":{}}
{"version":1,"id":"...","method":"cancel","params":{}}
{"version":1,"id":"...","method":"observe_codex_submit","params":{...}}
```

The daemon is single-flight only: one active dictation job at a time, with no queue.

## CLI

`dictate` talks to the daemon.

Commands:

```bash
dictate toggle --profile clean
dictate toggle --profile codex
dictate cancel
dictate status
dictate status --json
dictate terms init
dictate terms validate
dictate terms show --effective
dictate install-codex-hook
```

`dictate status` should be useful for debugging:

```text
state: recording
profile: clean
elapsed: 4.2s
speech: active
context: ~/.nixos-config
source: hyprland+tmux
delivery: clipboard_paste
learning: enabled
```

## Recording

Use CPAL first. Keep `pw-record` as a later fallback backend if CPAL proves fragile.

Pipeline:

```text
CPAL device-native input
  -> convert to mono 16 kHz PCM
  -> pre-roll ring buffer
  -> WebRTC VAD
  -> auto-stop after trailing silence
  -> WAV mono 16 kHz PCM16
  -> upload
```

Default behavior:

```text
toggle while idle:
  start recording / wait for speech

auto-stop:
  after trailing silence

toggle while recording:
  stop immediately and submit

cancel:
  discard

start timeout:
  return idle if no speech starts
```

Suggested defaults:

```toml
[recording]
auto_stop = true
start_timeout_ms = 10000
trailing_silence_ms = 1400
min_speech_ms = 350
max_recording_seconds = 120
pre_roll_ms = 300
silence_trim = true
```

## Endpoints

Support separate transcription and post-processing providers.

Transcription targets OpenAI-compatible Whisper endpoints:

```text
POST /v1/audio/transcriptions
multipart/form-data:
  file
  model
  prompt
  language
  temperature
```

Post-processing supports both:

```text
Chat Completions
Responses API
```

Important separation:

```text
profiles own behavior and prompts
providers own transport, model, auth, base URL
```

Example:

```toml
[transcription]
default_provider = "openai"

[transcription.providers.openai]
base_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
model = "whisper-1"
language = "en"

[postprocess]
default_provider = "default"

[postprocess.providers.default]
base_url = "https://api.openai.com/v1"
api_key_env = "OPENAI_API_KEY"
model = "gpt-5.5-mini"
wire_api = "chat_completions" # or "responses"
temperature = 0.1
```

Credentials are environment-variable based in v1. Config stores env var names only.

## Profiles

Default profile is faithful general cleanup:

```toml
[profiles.clean]
post_process = true
cleanup_prompt = "clean"
transcription_provider = "openai"
postprocess_provider = "default"

[profiles.raw]
post_process = false

[profiles.codex]
post_process = true
cleanup_prompt = "codex"
```

The `clean` profile is hard-preservation only:

```text
allowed:
  punctuation
  capitalization
  spacing
  obvious transcription errors
  dictionary corrections

forbidden:
  stylistic rewrite
  summarization
  added requirements
  changed intent
```

`codex` can later be more agent-instruction-oriented, but must still avoid inventing requirements.

## Dictionaries

Per-project authored terms live at the Git repo root:

```text
repo/.dictate/terms.toml
```

Created by:

```bash
dictate terms init
```

Example:

```toml
words = [
  "keyd",
  "mihomo",
  "nixfmt",
]

phrases = [
  "Home Manager",
  "OpenAI-compatible",
  "Whisper-compatible endpoint",
]

[terms]
"flake.nix" = "Nix flake entrypoint; preserve filename exactly"
"nixos-rebuild" = "NixOS rebuild command; preserve hyphenation"
"Codex CLI" = "OpenAI coding-agent command line tool; capitalize exactly"
```

No automatic term generation in v1. A later `dictate terms suggest` can scan repo files and propose terms for review.

Learned corrections are private/local by default:

```text
repo/.dictate/learned.toml
repo/.dictate/learned.pending.toml
```

`dictate terms init` should also create:

```gitignore
learned.toml
learned.pending.toml
sessions.*
```

## Context Resolution

Because multiple Codex TUIs may be open in different repos, v1 must resolve the focused project, not use "latest Codex context."

Use external tools in v1:

```text
hyprctl activewindow -j
tmux list-clients
tmux list-panes
procfs /proc/<pid>
```

Resolver chain:

```text
Hyprland focused window
  -> Alacritty window pid/class/title
  -> process tree / terminal relationship
  -> tmux client/pane mapping
  -> active pane cwd and command
  -> Codex hook context correlation
  -> Git repo root
```

Context confidence matters:

```text
high confidence:
  use project dictionary
  allow project learning writes

low confidence:
  paste still works
  use global terms only
  disable project learning
```

This protects learned correction files from being written to the wrong repo.

## Codex Integration

Use Codex's `UserPromptSubmit` hook for dictating into the interactive Codex prompt.

Hook config shape:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "dictate-codex-hook",
            "timeout": 1
          }
        ]
      }
    ]
  }
}
```

Hook behavior:

```text
read Codex hook payload from stdin
extract submitted prompt, cwd, and session metadata if present
send observe event to dictated over Unix socket
use very short timeout
always exit 0
never block prompt submission
```

This hook is for learning only. If the daemon is unavailable, Codex prompt submission must still proceed normally.

## Learning

Learning uses local diff heuristics only in v1.

Input:

```text
inserted cleaned text
final submitted Codex prompt
high-confidence project context
```

Guardrails:

```text
skip if context confidence is low
skip if insertion cannot be matched
skip if edit ratio is too high
skip if change is mostly insertion/deletion
skip if replacement spans are too long
skip if text contains newlines or broad rewrites
```

Promotion model:

```text
first observation:
  learned.pending.toml

same correction observed again:
  promote to learned.toml

manual rejection/approval:
  future command, not required for v1
```

Example pending record:

```toml
[[corrections]]
from = "nix OS"
to = "NixOS"
count = 1
first_seen = "2026-06-29T12:00:00Z"
last_seen = "2026-06-29T12:00:00Z"
```

Example promoted file:

```toml
[corrections]
"nix OS" = "NixOS"
"home manager" = "Home Manager"
```

## Delivery

Default delivery is temporary clipboard paste with best-effort restore.

For the target host:

```text
wl-paste reads current clipboard
wl-copy sets dictated text
ydotool sends Ctrl+V
after delay, wl-copy restores previous clipboard
```

Config:

```toml
[delivery]
backend = "clipboard_paste"
restore_clipboard = true
paste_delay_ms = 80
restore_delay_ms = 600
paste_key_backend = "ydotool"
```

Fallbacks:

```text
clipboard restore fails:
  leave dictated text on clipboard

paste key fails:
  optionally direct-type with wtype

context resolution fails:
  paste still proceeds
```

## Feedback

Use both sounds and persistent notifications.

Notification lifecycle:

```text
start:
  persistent "Dictation: Recording..."

speech detected:
  update "Listening..."

auto-stop/manual stop:
  update "Transcribing..."

post-process:
  update "Cleaning up..."

paste complete:
  close notification or briefly show "Pasted"

failure:
  critical notification with short actionable error
```

Use DBus notification API from Rust rather than relying only on `notify-send`, because v1 needs replacement and close behavior.

Sounds:

```text
recording_started
auto_stopped
pasted
failed
```

## Privacy

Default privacy policy:

```text
do not retain audio
do not retain failed audio unless debug is enabled
retain minimal text records needed for learning
do not retain full submitted prompts after correction extraction
do not log Authorization headers or API keys
```

Suggested config:

```toml
[privacy]
retain_audio = false
retain_failed_audio = false
retain_transcripts_days = 7
retain_observed_submissions = false
retain_debug_payloads = false
```

Persistent data:

```text
~/.config/dictate/config.toml
~/.config/dictate/secrets.env          # optional, chmod 600, not git
~/.config/dictate/terms.toml           # global authored terms

~/.local/state/dictate/sessions.sqlite # recent insertion/session metadata
~/.local/state/dictate/logs/           # redacted logs only

repo/.dictate/terms.toml               # committed project terms
repo/.dictate/learned.toml             # ignored/private
repo/.dictate/learned.pending.toml     # ignored/private
```

## Error Policy

Fail open for dictation, fail closed for learning.

```text
microphone fails:
  abort, notify

transcription fails:
  abort, notify

post-processing fails:
  paste raw transcript, notify

context resolver fails:
  use global dictionary only
  disable project learning

Codex hook fails:
  ignore, exit 0

clipboard restore fails:
  log/low-priority notify, do not undo paste

learning uncertain:
  skip learning
```

## Packaging

The Rust project should provide its own flake:

```text
packages.${system}.default
devShells.${system}.default
homeManagerModules.default
```

This NixOS repo consumes it as a separate input:

```nix
inputs.dictate-rs.url = "github:andongni/dictate-rs";
```

Then Home Manager enables the service and configures settings and keybinds. Since `dictated` needs microphone, Wayland, clipboard, notifications, and user runtime state, it should run as a Home Manager user service.

## Implementation Order

Even though v1 includes everything, build it in this dependency order:

```text
1. Rust workspace, config loading, IPC, daemon state machine
2. CLI: toggle/status/cancel
3. CPAL capture and WAV encoding
4. WebRTC VAD auto-stop
5. transcription provider
6. cleanup providers: Chat Completions + Responses
7. clipboard-paste delivery
8. DBus persistent notifications + sounds
9. project dictionary discovery and prompt construction
10. Hyprland/Alacritty/tmux context resolver
11. Codex hook adapter and hook installer
12. insertion session tracking
13. local diff learning and promotion
14. Nix flake + Home Manager module
```

## Required Spikes

Before hardening implementation, prove these four things on the target machine:

```text
Codex hook payload:
  log UserPromptSubmit stdin once and confirm exact fields for prompt/cwd/session

tmux mapping:
  prove focused Alacritty window can be mapped to active tmux pane cwd reliably

CPAL capture:
  confirm microphone capture, sample conversion, and VAD behavior under PipeWire

Mako notification replacement:
  confirm DBus notification replace/close works cleanly with Mako
```
