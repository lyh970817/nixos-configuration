#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
mkdir -p "$test_dir/bin" "$test_dir/home/.config/claude"
: >"$test_dir/home/.config/claude/orchestrator-opus.md"

cat >"$test_dir/bin/herdr" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"$HERDR_TEST_LOG"
printf '\n' >>"$HERDR_TEST_LOG"
case "$1:$2" in
  tab:list)
    if [[ -e $HERDR_TEST_STATE ]]; then
      printf '{"result":{"tabs":[{"tab_id":"w9:t1"},{"tab_id":"w9:t2"}]}}\n'
    else
      printf '{"result":{"tabs":[{"tab_id":"w9:t1"}]}}\n'
    fi
    ;;
  tab:create)
    : >"$HERDR_TEST_STATE"
    if [[ ${HERDR_TEST_CREATE_RESULT:-valid} == valid ]]; then
      printf '{"result":{"tab":{"tab_id":"w9:t2"},"root_pane":{"pane_id":"w9:p2"}}}\n'
    else
      printf '{"result":{"tab":{"tab_id":"w9:t2"}}}\n'
    fi
    ;;
  pane:list)
    if [[ -e $HERDR_TEST_STATE ]]; then
      printf '{"result":{"panes":[{"pane_id":"w9:p1"},{"pane_id":"w9:p3"}]}}\n'
    else
      printf '{"result":{"panes":[{"pane_id":"w9:p1"}]}}\n'
    fi
    ;;
  pane:split)
    : >"$HERDR_TEST_STATE"
    if [[ ${HERDR_TEST_CREATE_RESULT:-valid} == valid ]]; then
      printf '{"result":{"pane":{"pane_id":"w9:p3"}}}\n'
    else
      printf '{"result":{"pane":{}}}\n'
    fi
    ;;
  agent:start)
    : >"$HERDR_TEST_STARTED"
    [[ ${HERDR_TEST_START_RESULT:-success} == success ]]
    ;;
  agent:get)
    case "${HERDR_TEST_AFTER_FAILURE:-empty}" in
      detected) printf '{"result":{"agent":{"agent":"%s"}}}\n' "$HERDR_TEST_AGENT_KIND" ;;
      *) exit 1 ;;
    esac
    ;;
  pane:get)
    if [[ -e $HERDR_TEST_STARTED && ${HERDR_TEST_AFTER_FAILURE:-empty} == gone ]] \
      || [[ ! -e $HERDR_TEST_STARTED && ${HERDR_TEST_BEFORE_START:-idle} == gone ]]; then
      printf '{"error":{"code":"pane_not_found"}}\n'
      exit 1
    fi
    printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "$3"
    ;;
  pane:process-info)
    # The shell itself in the foreground and nothing else is Herdr's available
    # shell; any other pid means something is running in the pane.
    if [[ ! -e $HERDR_TEST_STARTED ]]; then
      case "${HERDR_TEST_BEFORE_START:-idle}" in
        idle) printf '{"result":{"process_info":{"shell_pid":100,"foreground_processes":[{"pid":100,"name":"zsh"}]}}}\n' ;;
        *) printf '{"result":{"process_info":{"shell_pid":100,"foreground_processes":[{"pid":100,"name":"zsh"},{"pid":101,"name":"fastfetch"}]}}}\n' ;;
      esac
      exit 0
    fi
    case "${HERDR_TEST_AFTER_FAILURE:-empty}" in
      running) printf '{"result":{"process_info":{"shell_pid":100,"foreground_processes":[{"pid":201,"name":"%s","argv":["/bin/%s"]}]}}}\n' "$HERDR_TEST_AGENT_KIND" "$HERDR_TEST_AGENT_KIND" ;;
      *) printf '{"result":{"process_info":{"shell_pid":100,"foreground_processes":[{"pid":100,"name":"zsh"}]}}}\n' ;;
    esac
    ;;
esac
MOCK
chmod +x "$test_dir/bin/herdr"

run_launch() {
  : >"$test_dir/log"
  rm -f -- "$test_dir/state" "$test_dir/started"
  PATH="$test_dir/bin:$PATH" \
    HOME="$test_dir/home" \
    HERDR_TEST_LOG="$test_dir/log" \
    HERDR_TEST_AGENT_KIND="${1:-}" \
    HERDR_TEST_STATE="$test_dir/state" \
    HERDR_TEST_STARTED="$test_dir/started" \
    HERDR_SOCKET_PATH="$test_dir/herdr.sock" \
    HERDR_ACTIVE_WORKSPACE_ID=w9 \
    HERDR_ACTIVE_PANE_ID=w9:p1 \
    HERDR_ACTIVE_PANE_CWD=/work/project \
    "$script_dir/herdr-agent-launch" "$@"
}

run_launch claude tab resume
grep -Fx "tab create --workspace w9 --cwd /work/project --no-focus " "$test_dir/log"
grep -Fx \
  "agent start claude-orch-w9p2 --kind claude --pane w9:p2 -- --dangerously-skip-permissions --model claude-opus-5 --append-system-prompt-file $test_dir/home/.config/claude/orchestrator-opus.md --resume " \
  "$test_dir/log"
grep -Fx "agent focus claude-orch-w9p2 " "$test_dir/log"

run_launch codex right resume
grep -Fx \
  "pane split --current --direction right --cwd /work/project --no-focus " \
  "$test_dir/log"
grep -Fx \
  "agent start codex-orch-w9p3 --kind codex --pane w9:p3 -- --profile orchestrator --yolo resume " \
  "$test_dir/log"
grep -Fx "agent focus codex-orch-w9p3 " "$test_dir/log"

run_launch codex down new
grep -Fx \
  "pane split --current --direction down --cwd /work/project --no-focus " \
  "$test_dir/log"
grep -Fx \
  "agent start codex-orch-w9p3 --kind codex --pane w9:p3 -- --profile orchestrator --yolo " \
  "$test_dir/log"

if run_launch claude diagonal new 2>/dev/null; then
  echo "invalid placement unexpectedly succeeded" >&2
  exit 1
fi

HERDR_TEST_START_RESULT=failure HERDR_TEST_AFTER_FAILURE=empty \
  run_launch codex right new 2>/dev/null || true
grep -Fx "pane close w9:p3 " "$test_dir/log"

HERDR_TEST_START_RESULT=failure HERDR_TEST_AFTER_FAILURE=empty \
  run_launch claude tab new 2>/dev/null || true
grep -Fx "tab close w9:t2 " "$test_dir/log"

HERDR_TEST_START_RESULT=failure HERDR_TEST_AFTER_FAILURE=detected \
  run_launch codex down new
grep -Fx "agent focus w9:p3 " "$test_dir/log"
if grep -Eq '^(pane|tab) close ' "$test_dir/log"; then
  echo "detected agent destination was unexpectedly rolled back" >&2
  exit 1
fi

HERDR_TEST_START_RESULT=failure HERDR_TEST_AFTER_FAILURE=running \
  run_launch claude tab new 2>/dev/null || true
if grep -Eq '^(pane|tab) close ' "$test_dir/log"; then
  echo "running agent destination was unexpectedly rolled back" >&2
  exit 1
fi

# A destination the user closed while the agent was starting: nothing to remove,
# and no failure to announce.
HERDR_TEST_START_RESULT=failure HERDR_TEST_AFTER_FAILURE=gone \
  run_launch claude right resume 2>/dev/null || true
if grep -Eq '^(pane|tab) close ' "$test_dir/log"; then
  echo "closed destination was unexpectedly rolled back" >&2
  exit 1
fi
if grep -Fq 'notification show' "$test_dir/log"; then
  echo "closed destination unexpectedly reported a failure" >&2
  exit 1
fi

# The same, for a destination closed before the shell ever went quiet.
HERDR_TEST_BEFORE_START=gone \
  run_launch codex tab resume 2>/dev/null || true
if grep -Eq '^(pane|tab) close ' "$test_dir/log"; then
  echo "destination closed during the shell wait was rolled back" >&2
  exit 1
fi
if grep -Fq 'notification show' "$test_dir/log"; then
  echo "destination closed during the shell wait reported a failure" >&2
  exit 1
fi

HERDR_TEST_CREATE_RESULT=malformed run_launch claude tab new 2>/dev/null || true
grep -Fx "tab close w9:t2 " "$test_dir/log"

HERDR_TEST_CREATE_RESULT=malformed run_launch codex right new 2>/dev/null || true
grep -Fx "pane close w9:p3 " "$test_dir/log"

echo "herdr-agent-launch tests passed"
