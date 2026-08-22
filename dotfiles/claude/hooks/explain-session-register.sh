#!/bin/sh
# Silent SessionStart hook: record which Claude session (and which launcher
# profile) lives in this Herdr pane, so scripts/herdr-explain-current can fork
# the exact session out-of-band. Herdr's own agent-session record carries the
# session ID but not the launcher; this mapping adds it. Prints nothing and
# exits 0 on every path — a hook failure must never surface in the session.

set -eu

[ -n "${HERDR_PANE_ID:-}" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

hook_input_file="$(mktemp "${TMPDIR:-/tmp}/explain-session-register.XXXXXX")" || exit 0
trap 'rm -f "$hook_input_file"' EXIT HUP INT TERM
cat >"$hook_input_file" 2>/dev/null || true

EXPLAIN_HOOK_INPUT_FILE="$hook_input_file" python3 - <<'PY' 2>/dev/null || true
import json
import os
import tempfile

pane_id = os.environ.get("HERDR_PANE_ID", "")
runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()

hook_input = {}
try:
    with open(os.environ["EXPLAIN_HOOK_INPUT_FILE"], encoding="utf-8") as handle:
        content = handle.read()
    if content.strip():
        hook_input = json.loads(content)
except Exception:
    hook_input = {}

session_id = hook_input.get("session_id")
if not session_id or hook_input.get("agent_id"):
    raise SystemExit(0)  # no session, or a subagent: nothing to record

config_dir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser(
    "~/.config/claude"
)
launcher = {
    "claude": "claude",
    "claude-gpt56": "claude-gpt56",
}.get(os.path.basename(os.path.normpath(config_dir)))

by_pane = os.path.join(runtime_dir, "explain-session", "by-pane")
os.makedirs(by_pane, mode=0o700, exist_ok=True)
os.chmod(os.path.dirname(by_pane), 0o700)
os.chmod(by_pane, 0o700)

record = {
    "session_id": session_id,
    "cwd": hook_input.get("cwd") or os.getcwd(),
    "transcript_path": hook_input.get("transcript_path"),
    "config_dir": config_dir,
    "launcher": launcher,
}

# A session ID grants access to private conversation history: private modes
# and an atomic replace, so readers never see a partial record.
target = os.path.join(by_pane, "%s.json" % pane_id.replace("/", "_"))
fd, temporary = tempfile.mkstemp(prefix=".register.", dir=by_pane)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2)
        handle.write("\n")
    os.chmod(temporary, 0o600)
    os.replace(temporary, target)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
PY

exit 0
