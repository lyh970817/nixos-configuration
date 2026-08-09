#!/usr/bin/env bash
# PreToolUse hook on the Agent tool. `agent_id` is absent in the main session
# and present inside a subagent, so this only sees direct reports.
set -euo pipefail

input="$(cat)"

[ -z "$(jq -r '.agent_id // empty' <<<"$input")" ] || exit 0

prompt="$(jq -r '.tool_input.prompt // empty' <<<"$input")"

for marker in 'done:' 'blocked:' 'needs-decision:' 'failed:'; do
  case "$prompt" in
    *"$marker"*) ;;
    *)
      cat >&2 <<'EOF'
This is a direct report and its prompt carries no return contract. Append one
and spawn again:

  Reply with one line — done: / blocked: / needs-decision: / failed: plus
  one sentence. If you were asked to find something out, include your
  conclusions as well.
EOF
      exit 2
      ;;
  esac
done
