#!@bash@
# Fail-open Codex hook: perform only one bounded local datagram enqueue.
set +e

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(@coreutils@/id -u)}"
target="$runtime_dir/herdr-title/events.sock"

# Codex 0.147 does not support async SessionStart/UserPromptSubmit hooks. Keep
# this synchronous compatibility shim below 100 ms and do no state/network work.
@coreutils@/timeout 0.1 @bash@ -c '
  @jq@ -c \
    --arg socket "${HERDR_SOCKET_PATH:-}" \
    --arg pane_id "${HERDR_PANE_ID:-}" \
    --arg tab_id "${HERDR_TAB_ID:-}" '\''
      select((.agent_id // "") == "" and (.agent_type // "") == "")
      | select(.hook_event_name == "SessionStart" or .hook_event_name == "UserPromptSubmit")
      | {
          version: 1,
          type: (if .hook_event_name == "SessionStart" then "codex_session" else "codex_prompt" end),
          session_id: ((.session_id // "") | tostring | .[:256]),
          turn_id: ((.turn_id // "") | tostring | .[:256]),
          cwd: ((.cwd // "") | tostring | .[:4096]),
          source: ((.source // "") | tostring | .[:64]),
          prompt: (if .hook_event_name == "UserPromptSubmit" then ((.prompt // "") | tostring | .[:4000]) else null end),
          socket: $socket,
          pane_id: $pane_id,
          tab_id: $tab_id
        }
    '\'' \
    | @nc@ -u -U -w 0 -- "$1"
' _ "$target" 2>/dev/null

exit 0
