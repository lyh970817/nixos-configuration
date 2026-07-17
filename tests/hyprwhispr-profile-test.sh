#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
selector="$repo_root/scripts/hyprwhispr-profile"
profile_ensure="$repo_root/scripts/hyprwhispr-profile-ensure"
record_wrapper="$repo_root/scripts/hyprwhispr-record"
fixtures="$repo_root/config/hyprwhspr/profiles"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected '$1' to contain '$2'"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "expected '$1' not to contain '$2'"; }

jq -e \
  '.transcription_backend == "rest-api" and .rest_api_provider == "openrouter" and .rest_endpoint_url == "https://openrouter.ai/api/v1/audio/transcriptions" and .rest_body.model == "openai/gpt-4o-mini-transcribe" and .post_transcription_hook == null' \
  "$fixtures/4o-mini.json" >/dev/null || fail 'invalid 4o-mini immutable profile'
jq -e \
  '.transcription_backend == "realtime-ws" and .websocket_provider == "openai" and .websocket_model == "gpt-4o-mini-transcribe" and .realtime_mode == "transcribe" and (has("realtime_transcription_delay") | not) and .post_transcription_hook == null' \
  "$fixtures/realtime.json" >/dev/null || fail 'invalid realtime immutable profile'
[[ "$(find "$fixtures" -maxdepth 1 -name '*.json' -printf '%f\n' | sort)" == $'4o-mini.json\nrealtime.json' ]] || fail 'profile set is not exactly realtime and 4o-mini'

adapter_dir="$workdir/adapters"
mkdir -p "$adapter_dir" "$workdir/state" "$workdir/runtime"
service_log="$workdir/service.log"
notify_log="$workdir/notify.log"
event_log="$workdir/event.log"
cat > "$adapter_dir/activity" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${TEST_ACTIVITY_COUNTER_FILE:-}" ]]; then
  count="$(<"$TEST_ACTIVITY_COUNTER_FILE")"
  count=$((count + 1))
  printf '%s\n' "$count" > "$TEST_ACTIVITY_COUNTER_FILE"
  printf 'activity-check %s\n' "$count" >> "$TEST_EVENT_LOG"
  if (( count >= ${TEST_ACTIVITY_BUSY_ON_CALL:-2} )); then
    printf '%s\n' "${TEST_ACTIVITY_AFTER_FIRST:-normal-recording}"
  fi
  exit 0
fi
if [[ -r "${TEST_ACTIVITY_FILE:-}" ]]; then
  activity="$(<"$TEST_ACTIVITY_FILE")"
  printf 'activity %s\n' "$activity" >> "$TEST_EVENT_LOG"
  printf '%s\n' "$activity"
fi
EOF
cat > "$adapter_dir/service" <<'EOF'
#!/usr/bin/env bash
printf '%s %s %s\n' "$1" "$2" "$3" >> "$TEST_SERVICE_LOG"
printf '%s %s %s\n' "$1" "$2" "$3" >> "$TEST_EVENT_LOG"
if [[ "$1" == active && "$2" == hyprwhspr.service ]]; then
  [[ "${TEST_NORMAL_SERVICE_ACTIVE:-false}" == true ]]
  exit
fi
if [[ "$1" == restart && -e "${TEST_FAIL_RESTART_ONCE:-}" ]]; then
  rm -f "$TEST_FAIL_RESTART_ONCE"
  exit 1
fi
EOF
cat > "$adapter_dir/notify" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$1" "$2" >> "$TEST_NOTIFY_LOG"
printf 'notify %s\n' "$2" >> "$TEST_EVENT_LOG"
EOF
chmod +x "$adapter_dir"/*

export HYPRWHISPR_PROFILE_PROFILES_DIR="$fixtures"
export HYPRWHISPR_PROFILE_STATE_HOME="$workdir/state"
export HYPRWHISPR_PROFILE_RUNTIME_DIR="$workdir/runtime"
export HYPRWHISPR_PROFILE_ACTIVITY_ADAPTER="$adapter_dir/activity"
export HYPRWHISPR_PROFILE_SERVICE_ADAPTER="$adapter_dir/service"
export HYPRWHISPR_PROFILE_NOTIFY_ADAPTER="$adapter_dir/notify"
export TEST_SERVICE_LOG="$service_log"
export TEST_NOTIFY_LOG="$notify_log"
export TEST_EVENT_LOG="$event_log"
credential_sentinel='openrouter-credential-sentinel-do-not-print'
export HYPRWHISPR_PROFILE_CREDENTIAL_SENTINEL="$credential_sentinel"

ensure_selector="$adapter_dir/ensure-selector"
ensure_log="$workdir/ensure.log"
cat > "$ensure_selector" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_ENSURE_LOG"
exec "$TEST_REAL_SELECTOR" "$@"
EOF
chmod +x "$ensure_selector"
export HYPRWHISPR_PROFILE_SELECTOR="$ensure_selector"
export TEST_ENSURE_LOG="$ensure_log"
export TEST_REAL_SELECTOR="$selector"

assert_eq "$("$selector" status)" 4o-mini
assert_eq "$(<"$workdir/state/hyprwhispr-profile/mode")" 4o-mini
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/4o-mini.json"

"$profile_ensure"
[[ ! -e "$ensure_log" ]] || fail 'matching prestart re-entered the selector'

ln -sfn "$fixtures/realtime.json" "$workdir/runtime/config.json"
"$profile_ensure"
assert_eq "$(<"$ensure_log")" status
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/4o-mini.json"

: > "$ensure_log"
printf 'invalid\n' > "$workdir/state/hyprwhispr-profile/mode"
"$profile_ensure"
assert_eq "$(<"$ensure_log")" status
assert_eq "$(<"$workdir/state/hyprwhispr-profile/mode")" 4o-mini

: > "$ensure_log"
rm "$workdir/runtime/config.json"
"$profile_ensure"
assert_eq "$(<"$ensure_log")" status
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/4o-mini.json"
rm "$ensure_log"

record_adapter="$adapter_dir/record-command"
record_log="$workdir/record.log"
cat > "$record_adapter" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$XDG_CONFIG_HOME" "$*" > "$TEST_RECORD_LOG"
if [[ "$*" == 'record toggle' ]]; then
  (
    sleep 0.2
    mkdir -p "$XDG_CONFIG_HOME/hyprwhspr"
    printf 'true\n' > "$XDG_CONFIG_HOME/hyprwhspr/recording_status"
  ) &
fi
EOF
chmod +x "$record_adapter"
exec 8>"$workdir/state/hyprwhispr-profile.lock"
flock -x 8
HYPRWHISPR_RECORD_COMMAND="$record_adapter" \
  XDG_RUNTIME_DIR="$workdir/runtime-home" \
  TEST_RECORD_LOG="$record_log" \
  "$record_wrapper" toggle &
record_pid=$!
sleep 0.1
kill -0 "$record_pid" || fail 'record wrapper did not wait for the profile transaction lock'
[[ ! -e "$record_log" ]] || fail 'record wrapper crossed the profile transaction lock'
flock -u 8
wait "$record_pid"
assert_eq "$(<"$record_log")" "$workdir/runtime-home|record toggle"
assert_eq "$(<"$workdir/runtime-home/hyprwhspr/recording_status")" true

printf 'obsolete\n' > "$workdir/state/hyprwhispr-profile/mode"
assert_eq "$("$selector" status)" 4o-mini
printf '4o-mini\n\n' > "$workdir/state/hyprwhispr-profile/mode"
assert_eq "$("$selector" status)" 4o-mini
printf 'realtime\ntrailing-bytes' > "$workdir/state/hyprwhispr-profile/mode"
assert_eq "$("$selector" status)" 4o-mini
assert_eq "$("$selector" set realtime)" realtime
assert_eq "$("$selector" status)" realtime
assert_contains "$(<"$notify_log")" 'Hyprwhispr profile active|realtime'
assert_contains "$(<"$event_log")" $'restart hyprwhspr.service realtime\nhealth hyprwhspr.service realtime\nrestart meeting-recorder.service realtime\nhealth meeting-recorder.service realtime\nnotify realtime'
assert_eq "$("$selector" toggle)" 4o-mini
assert_eq "$("$selector" toggle)" realtime
assert_eq "$("$selector" status)" realtime
assert_eq "$("$selector" set realtime)" realtime

before_state="$(<"$workdir/state/hyprwhispr-profile/mode")"
before_link="$(readlink -f "$workdir/runtime/config.json")"
before_service="$(<"$service_log")"
if "$selector" set legacy >"$workdir/invalid.out" 2>&1; then fail 'invalid mode succeeded'; fi
assert_eq "$(<"$workdir/state/hyprwhispr-profile/mode")" "$before_state"
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$before_link"
assert_eq "$(<"$service_log")" "$before_service"

for activity in normal-recording normal-processing longform-recording longform-processing; do
  printf '%s\n' "$activity" > "$workdir/activity"
  export TEST_ACTIVITY_FILE="$workdir/activity"
  for requested in realtime 4o-mini; do
    before_service="$(<"$service_log")"
    before_notify="$(<"$notify_log")"
    if "$selector" set "$requested" >"$workdir/busy.out" 2>&1; then fail "$activity allowed a change"; else busy_status=$?; fi
    assert_eq "$busy_status" 3
    busy_output="$(<"$workdir/busy.out")"
    busy_notify="$(tail -n 1 "$notify_log")"
    busy_events="$(tail -n 2 "$event_log")"
    assert_contains "$busy_output" "$activity"
    assert_contains "$busy_output" 'profile unchanged'
    assert_eq "$busy_notify" "Hyprwhispr profile unchanged|Current profile is realtime; dictation is busy ($activity)."
    assert_eq "$busy_events" "activity $activity"$'\n'"notify Current profile is realtime; dictation is busy ($activity)."
    assert_eq "$(<"$notify_log")" "$before_notify"$'\n'"$busy_notify"
    [[ "$busy_notify" != *'Hyprwhispr profile active'* ]] || fail 'busy refusal sent a success notification'
    assert_not_contains "$busy_output" "$fixtures"
    assert_not_contains "$busy_output" "$credential_sentinel"
    assert_not_contains "$busy_notify" "$fixtures"
    assert_not_contains "$busy_notify" "$credential_sentinel"
    assert_eq "$(<"$workdir/state/hyprwhispr-profile/mode")" realtime
    assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/realtime.json"
    assert_eq "$(<"$service_log")" "$before_service"
    assert_not_contains "$busy_events" "$fixtures"
    assert_not_contains "$busy_events" "$credential_sentinel"
  done
done
unset TEST_ACTIVITY_FILE

printf '0\n' > "$workdir/activity-counter"
export TEST_ACTIVITY_COUNTER_FILE="$workdir/activity-counter"
export TEST_ACTIVITY_AFTER_FIRST=normal-recording
before_service_lines="$(wc -l < "$service_log")"
before_notify="$(<"$notify_log")"
if "$selector" set 4o-mini >"$workdir/late-busy.out" 2>&1; then fail 'activity beginning during profile preparation allowed a change'; else late_busy_status=$?; fi
assert_eq "$late_busy_status" 3
assert_eq "$(<"$workdir/state/hyprwhispr-profile/mode")" realtime
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/realtime.json"
late_busy_service_events="$(tail -n "+$((before_service_lines + 1))" "$service_log")"
assert_eq "$late_busy_service_events" 'active meeting-recorder.service realtime'
assert_not_contains "$late_busy_service_events" restart
assert_eq "$(<"$notify_log")" "$before_notify"$'\n''Hyprwhispr profile unchanged|Current profile is realtime; dictation is busy (normal-recording).'
unset TEST_ACTIVITY_COUNTER_FILE TEST_ACTIVITY_AFTER_FIRST

export TEST_NORMAL_SERVICE_ACTIVE=true
ln -sfn "$fixtures/4o-mini.json" "$workdir/runtime/config.json"
printf 'normal-recording\n' > "$workdir/activity"
export TEST_ACTIVITY_FILE="$workdir/activity"
before_service="$(<"$service_log")"
if "$selector" status >"$workdir/busy-status.out" 2>&1; then fail 'busy status repaired a drifted profile'; else busy_status=$?; fi
assert_eq "$busy_status" 3
assert_eq "$(<"$workdir/state/hyprwhispr-profile/mode")" realtime
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/4o-mini.json"
assert_eq "$(<"$service_log")" "$before_service"
unset TEST_ACTIVITY_FILE
before_service_lines="$(wc -l < "$service_log")"
assert_eq "$("$selector" status)" realtime
assert_contains "$(tail -n "+$((before_service_lines + 1))" "$service_log")" 'restart hyprwhspr.service realtime'
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/realtime.json"
unset TEST_NORMAL_SERVICE_ACTIVE

touch "$workdir/fail-restart"
export TEST_FAIL_RESTART_ONCE="$workdir/fail-restart"
if "$selector" set 4o-mini >"$workdir/rollback.out" 2>&1; then fail 'failing restart succeeded'; fi
assert_contains "$(<"$workdir/rollback.out")" 'restored realtime'
assert_eq "$("$selector" status)" realtime
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/realtime.json"
assert_contains "$(<"$service_log")" $'restart hyprwhspr.service 4o-mini\nrestart hyprwhspr.service realtime\nhealth hyprwhspr.service realtime\nrestart meeting-recorder.service realtime\nhealth meeting-recorder.service realtime'
assert_contains "$(<"$notify_log")" 'Hyprwhispr profile change failed|Restored realtime'

assert_eq "$("$selector" set 4o-mini)" 4o-mini
touch "$workdir/fail-restart"
export TEST_FAIL_RESTART_ONCE="$workdir/fail-restart"
if "$selector" set realtime >"$workdir/rollback-other.out" 2>&1; then fail 'second failing restart succeeded'; fi
assert_contains "$(<"$workdir/rollback-other.out")" 'restored 4o-mini'
assert_eq "$("$selector" status)" 4o-mini
assert_eq "$(readlink -f "$workdir/runtime/config.json")" "$fixtures/4o-mini.json"

{
  "$selector" status
  "$selector" set realtime
} >"$workdir/selector.out" 2>&1
if rg -F "$credential_sentinel" "$workdir/state" "$workdir/runtime" "$service_log" "$notify_log" "$workdir/selector.out"; then
  fail 'credential sentinel leaked from the selector'
fi

if rg -n -i '(api[_-]?key|secret|token)' "$workdir/state" "$workdir/runtime" "$service_log" "$notify_log"; then
  fail 'observable selector artifacts contain credential material'
fi

printf 'hyprwhispr-profile tests passed\n'
