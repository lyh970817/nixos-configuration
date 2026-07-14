#!/usr/bin/env bash
# Test a Mihomo-related NixOS generation behind a short, independent rollback
# timer. The timer runs a root-owned volatile helper that restores the exact
# known-good closure without evaluating the flake or reading repository state.
set -euo pipefail

readonly REPO_DIR="/home/andongni/Yandex.Disk/System/nixos-configuration"
readonly MIHOMO_CONFIG="mihomo-config.yaml"
readonly MIHOMO_IDENTITY="mihomo-config.sha256"
readonly MIHOMO_MODULE="modules/services/mihomo.nix"
readonly SYSTEM_PROFILE="/nix/var/nix/profiles/system"
readonly STATE_DIR="/run/mihomo-safe-rebuild"
readonly STATE_FILE="$STATE_DIR/current"
readonly LOCK_FILE="/run/lock/mihomo-safe-rebuild.lock"
readonly TIMER_PREFIX="mihomo-safe-rebuild-rollback"
readonly ROLLBACK_SECONDS=90
readonly CONFIRM_DELAY_SECONDS=20
readonly BUILD_TIMEOUT_SECONDS=3600
# This only bounds the caller's wait. Work already submitted to PID 1 may
# continue, so the rollback helper remains responsible for recovery.
readonly ACTIVATION_TIMEOUT_SECONDS=10
readonly SYSTEMCTL_TIMEOUT_SECONDS=15
readonly PROFILE_TIMEOUT_SECONDS=30
readonly BOOT_TIMEOUT_SECONDS=30
readonly RECOVERY_READINESS_SECONDS=20
readonly MIHOMO_REST_URL="http://127.0.0.1:9090/configs"

transaction=""
known_good=""
candidate=""
timer_unit=""
rollback_helper=""
activated_at=0
expires_at=0
phase=""

die() {
  printf 'mihomo-safe-rebuild: %s\n' "$*" >&2
  exit 1
}

note() {
  printf 'mihomo-safe-rebuild: %s\n' "$*"
}

require_root() {
  [[ $EUID -eq 0 ]] || die "run this command with sudo"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

run_bounded() {
  local seconds=$1
  shift
  timeout --kill-after=1s "${seconds}s" "$@"
}

current_system() {
  readlink -f /run/current-system
}

profile_system() {
  readlink -f "$SYSTEM_PROFILE"
}

assert_safe_transaction_id() {
  [[ $1 =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid transaction id"
}

acquire_lock() {
  install -d -m 0755 -o root -g root "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "another Mihomo safe-rebuild command is running"
}

prepare_state_dir() {
  install -d -m 0700 -o root -g root "$STATE_DIR"
}

clear_state() {
  rm -f "$STATE_FILE" "${rollback_helper:-}"
}

write_state() {
  local temporary

  prepare_state_dir
  temporary=$(mktemp "$STATE_DIR/.current.XXXXXX")
  chmod 0600 "$temporary"
  {
    printf 'transaction=%s\n' "$transaction"
    printf 'known_good=%s\n' "$known_good"
    printf 'candidate=%s\n' "$candidate"
    printf 'timer_unit=%s\n' "$timer_unit"
    printf 'rollback_helper=%s\n' "$rollback_helper"
    printf 'activated_at=%s\n' "$activated_at"
    printf 'expires_at=%s\n' "$expires_at"
    printf 'phase=%s\n' "$phase"
  } >"$temporary"
  mv -f "$temporary" "$STATE_FILE"
}

load_state() {
  local key
  local value

  [[ -f "$STATE_FILE" ]] || return 1
  [[ ! -L "$STATE_FILE" ]] || die "transaction state must not be a symlink"
  [[ $(stat -c '%u:%a' "$STATE_FILE") == '0:600' ]] ||
    die "transaction state must be root-owned with mode 0600"

  transaction=""
  known_good=""
  candidate=""
  timer_unit=""
  rollback_helper=""
  activated_at=""
  expires_at=""
  phase=""
  while IFS='=' read -r key value || [[ -n $key ]]; do
    case $key in
      transaction)
        [[ -z $transaction ]] || die "duplicate transaction state field"
        transaction=$value
        ;;
      known_good)
        [[ -z $known_good ]] || die "duplicate transaction state field"
        known_good=$value
        ;;
      candidate)
        [[ -z $candidate ]] || die "duplicate transaction state field"
        candidate=$value
        ;;
      timer_unit)
        [[ -z $timer_unit ]] || die "duplicate transaction state field"
        timer_unit=$value
        ;;
      rollback_helper)
        [[ -z $rollback_helper ]] || die "duplicate transaction state field"
        rollback_helper=$value
        ;;
      activated_at)
        [[ -z $activated_at ]] || die "duplicate transaction state field"
        activated_at=$value
        ;;
      expires_at)
        [[ -z $expires_at ]] || die "duplicate transaction state field"
        expires_at=$value
        ;;
      phase)
        [[ -z $phase ]] || die "duplicate transaction state field"
        phase=$value
        ;;
      *) die "invalid transaction state field" ;;
    esac
  done <"$STATE_FILE"

  assert_safe_transaction_id "$transaction"
  [[ $known_good == /nix/store/* && -x "$known_good/bin/switch-to-configuration" ]] ||
    die "invalid known-good closure in transaction state"
  [[ $candidate == /nix/store/* && -x "$candidate/bin/switch-to-configuration" ]] ||
    die "invalid candidate closure in transaction state"
  [[ $timer_unit == "$TIMER_PREFIX-$transaction.timer" ]] ||
    die "invalid timer unit in transaction state"
  [[ $rollback_helper == "$STATE_DIR/rollback-$transaction" && -x $rollback_helper ]] ||
    die "invalid rollback helper in transaction state"
  [[ $activated_at =~ ^[0-9]+$ ]] || die "invalid activation time in transaction state"
  [[ $expires_at =~ ^[0-9]+$ ]] || die "invalid expiration time in transaction state"
  [[ $phase == armed || $phase == confirmed || $phase == rolled-back ]] ||
    die "invalid transaction phase in transaction state"
}

timer_service_unit() {
  printf '%s.service\n' "${timer_unit%.timer}"
}

timer_is_armed() {
  run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-active --quiet "$timer_unit"
}

stop_rollback_units() {
  local load_state
  local unit

  for unit in "$timer_unit" "$(timer_service_unit)"; do
    load_state=$(run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" \
      systemctl show --value -p LoadState "$unit" 2>/dev/null || true)
    [[ $load_state == not-found ]] && continue
    [[ -n $load_state ]] || die "could not inspect rollback unit $unit"
    if ! run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl stop "$unit"; then
      load_state=$(run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" \
        systemctl show --value -p LoadState "$unit" 2>/dev/null || true)
      [[ $load_state == not-found ]] ||
        die "could not stop rollback unit $unit"
    fi
  done
}

known_good_command_path() {
  local command_name=$1
  local path="$known_good/sw/bin/$command_name"

  if [[ ! -x $path ]]; then
    path=$(command -v "$command_name")
  fi
  [[ -x $path ]] || die "required recovery command is unavailable: $command_name"
  # Preserve the symlink basename. NixOS Coreutils dispatches applets through
  # argv[0], so resolving this path to the multicall binary would break it.
  printf '%s\n' "$path"
}

write_rollback_helper() {
  local bash_path
  local curl_path
  local date_path
  local flock_path
  local nix_env_path
  local readlink_path
  local rm_path
  local sleep_path
  local systemctl_path
  local temporary
  local timeout_path

  prepare_state_dir
  bash_path=$(known_good_command_path bash)
  curl_path=$(known_good_command_path curl)
  date_path=$(known_good_command_path date)
  flock_path=$(known_good_command_path flock)
  nix_env_path=$(known_good_command_path nix-env)
  readlink_path=$(known_good_command_path readlink)
  rm_path=$(known_good_command_path rm)
  sleep_path=$(known_good_command_path sleep)
  systemctl_path=$(known_good_command_path systemctl)
  timeout_path=$(known_good_command_path timeout)
  rollback_helper="$STATE_DIR/rollback-$transaction"
  temporary=$(mktemp "$STATE_DIR/.rollback.XXXXXX")
  chmod 0700 "$temporary"
  {
    printf '#!%s\n' "$bash_path"
    printf 'readonly EXPECTED_TRANSACTION=%q\n' "$transaction"
    printf 'readonly LOCK_FILE=%q\n' "$LOCK_FILE"
    printf 'readonly STATE_FILE=%q\n' "$STATE_FILE"
    printf 'readonly SYSTEM_PROFILE=%q\n' "$SYSTEM_PROFILE"
    printf 'readonly MIHOMO_REST_URL=%q\n' "$MIHOMO_REST_URL"
    printf 'readonly PROFILE_TIMEOUT_SECONDS=%q\n' "$PROFILE_TIMEOUT_SECONDS"
    printf 'readonly BOOT_TIMEOUT_SECONDS=%q\n' "$BOOT_TIMEOUT_SECONDS"
    printf 'readonly ACTIVATION_TIMEOUT_SECONDS=%q\n' "$ACTIVATION_TIMEOUT_SECONDS"
    printf 'readonly RECOVERY_READINESS_SECONDS=%q\n' "$RECOVERY_READINESS_SECONDS"
    printf 'readonly CURL=%q\n' "$curl_path"
    printf 'readonly DATE=%q\n' "$date_path"
    printf 'readonly FLOCK=%q\n' "$flock_path"
    printf 'readonly NIX_ENV=%q\n' "$nix_env_path"
    printf 'readonly READLINK=%q\n' "$readlink_path"
    printf 'readonly RM=%q\n' "$rm_path"
    printf 'readonly SLEEP=%q\n' "$sleep_path"
    printf 'readonly SYSTEMCTL=%q\n' "$systemctl_path"
    printf 'readonly TIMEOUT=%q\n' "$timeout_path"
    cat <<'EOF'
set -euo pipefail

exec 9>"$LOCK_FILE"
"$FLOCK" 9

[[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] || exit 0

transaction=""
known_good=""
phase=""
while IFS='=' read -r key value || [[ -n $key ]]; do
  case $key in
    transaction)
      [[ -z $transaction ]] || exit 1
      transaction=$value
      ;;
    known_good)
      [[ -z $known_good ]] || exit 1
      known_good=$value
      ;;
    phase)
      [[ -z $phase ]] || exit 1
      phase=$value
      ;;
    candidate|timer_unit|rollback_helper|activated_at|expires_at) ;;
    *) exit 1 ;;
  esac
done <"$STATE_FILE"

[[ $transaction == "$EXPECTED_TRANSACTION" && $phase == armed ]] || exit 0
[[ $known_good == /nix/store/* && -x "$known_good/bin/switch-to-configuration" ]] || exit 1

if [[ $("$READLINK" -f "$SYSTEM_PROFILE") != "$known_good" ]]; then
  "$TIMEOUT" --kill-after=1s "${PROFILE_TIMEOUT_SECONDS}s" \
    "$NIX_ENV" --profile "$SYSTEM_PROFILE" --set "$known_good" || exit 1
  "$TIMEOUT" --kill-after=1s "${BOOT_TIMEOUT_SECONDS}s" \
    "$known_good/bin/switch-to-configuration" boot || true
fi

# A timed-out client does not imply failure: validate the resulting runtime.
"$TIMEOUT" --kill-after=1s "${ACTIVATION_TIMEOUT_SECONDS}s" \
  "$known_good/bin/switch-to-configuration" test || true
readiness_deadline=$(( $("$DATE" +%s) + RECOVERY_READINESS_SECONDS ))
while (( $("$DATE" +%s) < readiness_deadline )); do
  if [[ $("$READLINK" -f /run/current-system) == "$known_good" &&
    $("$READLINK" -f "$SYSTEM_PROFILE") == "$known_good" ]] &&
    "$SYSTEMCTL" is-active --quiet mihomo.service &&
    "$CURL" --fail --silent --output /dev/null --max-time 1 "$MIHOMO_REST_URL"; then
    "$RM" -f "$STATE_FILE" "$0"
    exit 0
  fi
  "$SLEEP" 1
done
exit 1
EOF
  } >"$temporary"
  mv -f "$temporary" "$rollback_helper"
}

assert_dedicated_mihomo_commit() {
  local changed
  local saw_mihomo=0

  for changed in "$MIHOMO_IDENTITY" "$MIHOMO_MODULE"; do
    git -C "$REPO_DIR" diff --quiet -- "$changed" ||
      die "$changed has uncommitted changes; commit the dedicated Mihomo change first"
    git -C "$REPO_DIR" diff --cached --quiet -- "$changed" ||
      die "$changed has staged changes; commit the dedicated Mihomo change first"
  done

  while IFS= read -r changed; do
    [[ -n $changed ]] || continue
    case $changed in
      "$MIHOMO_IDENTITY"|"$MIHOMO_MODULE") saw_mihomo=1 ;;
      *) die "HEAD is not a dedicated Mihomo commit; it also changes $changed" ;;
    esac
  done < <(git -C "$REPO_DIR" diff-tree --root --no-commit-id --name-only -r HEAD)
  (( saw_mihomo == 1 )) ||
    die "HEAD does not contain a Mihomo configuration identity or service-module change"
}

assert_mihomo_config_identity() {
  local actual
  local expected
  local identity_lines=()

  [[ -f "$REPO_DIR/$MIHOMO_CONFIG" ]] || die "$MIHOMO_CONFIG is missing"
  [[ -f "$REPO_DIR/$MIHOMO_IDENTITY" ]] || die "$MIHOMO_IDENTITY is missing"
  mapfile -t identity_lines <"$REPO_DIR/$MIHOMO_IDENTITY"
  (( ${#identity_lines[@]} == 1 )) ||
    die "$MIHOMO_IDENTITY must contain exactly one SHA-256 hash"
  expected=${identity_lines[0]}
  [[ $expected =~ ^[0-9a-f]{64}$ ]] ||
    die "$MIHOMO_IDENTITY does not contain a valid lowercase SHA-256 hash"
  actual=$(sha256sum -- "$REPO_DIR/$MIHOMO_CONFIG")
  actual=${actual%% *}
  [[ $actual == "$expected" ]] ||
    die "$MIHOMO_CONFIG does not match $MIHOMO_IDENTITY; update and commit the identity file"
}

build_candidate() {
  note "building the candidate system closure before arming rollback"
  candidate=$(run_bounded "$BUILD_TIMEOUT_SECONDS" nix build --impure --no-link --print-out-paths \
    "$REPO_DIR#nixosConfigurations.andongni.config.system.build.toplevel")
  [[ $candidate == /nix/store/* && -x "$candidate/bin/switch-to-configuration" ]] ||
    die "Nix did not return a NixOS system closure"
}

clear_completed_volatile_state() {
  if ! load_state; then
    return 0
  fi

  if [[ $phase == confirmed || $phase == rolled-back ]] && ! timer_is_armed; then
    clear_state
    return 0
  fi

  die "transaction $transaction is still pending; use status, confirm, or rollback $transaction"
}

arm_rollback_timer() {
  if ! run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemd-run \
    --unit="${timer_unit%.timer}" \
    --on-active="${ROLLBACK_SECONDS}s" \
    --timer-property=AccuracySec=1s \
    --timer-property=RemainAfterElapse=no \
    --collect \
    --service-type=oneshot \
    --property=TimeoutStartSec=150s \
    --description="Rollback guarded Mihomo deployment $transaction" \
    "$rollback_helper"; then
    clear_state
    die "could not arm the rollback timer; candidate was not activated"
  fi
  timer_is_armed || {
    clear_state
    die "rollback timer did not become active; candidate was not activated"
  }
}

restore_known_good() {
  local readiness_deadline

  note "restoring known-good closure $known_good"
  if [[ $(profile_system) != "$known_good" ]]; then
    run_bounded "$PROFILE_TIMEOUT_SECONDS" nix-env --profile "$SYSTEM_PROFILE" --set "$known_good" || return 1
    run_bounded "$BOOT_TIMEOUT_SECONDS" "$known_good/bin/switch-to-configuration" boot || true
  fi
  run_bounded "$ACTIVATION_TIMEOUT_SECONDS" "$known_good/bin/switch-to-configuration" test || true
  readiness_deadline=$(( $(date +%s) + RECOVERY_READINESS_SECONDS ))
  wait_for_system_ready "$known_good" "$readiness_deadline"
}

mihomo_rest_ready() {
  curl --fail --silent --output /dev/null --max-time 1 "$MIHOMO_REST_URL"
}

candidate_is_ready() {
  [[ $(current_system) == "$candidate" ]] &&
    systemctl is-active --quiet mihomo.service &&
    mihomo_rest_ready
}

system_is_ready() {
  local expected=$1

  [[ $(current_system) == "$expected" && $(profile_system) == "$expected" ]] &&
    systemctl is-active --quiet mihomo.service &&
    mihomo_rest_ready
}

wait_for_candidate_ready() {
  local deadline=$1

  while (( $(date +%s) < deadline )); do
    candidate_is_ready && return 0
    sleep 1
  done
  return 1
}

wait_for_system_ready() {
  local expected=$1
  local deadline=$2

  while (( $(date +%s) < deadline )); do
    system_is_ready "$expected" && return 0
    sleep 1
  done
  return 1
}

switch_candidate() {
  [[ $# -eq 0 ]] || die "usage: $0 switch"
  acquire_lock
  clear_completed_volatile_state
  assert_dedicated_mihomo_commit
  assert_mihomo_config_identity
  build_candidate
  # Detect YAML changes during the build before arming a rollback deadline.
  assert_mihomo_config_identity

  known_good=$(current_system)
  [[ $(profile_system) == "$known_good" ]] ||
    die "active system differs from the persistent system profile; recover it before starting"
  [[ $known_good == /nix/store/* && -x "$known_good/bin/switch-to-configuration" ]] ||
    die "persistent system profile is not a NixOS closure"

  transaction="$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')"
  timer_unit="$TIMER_PREFIX-$transaction.timer"
  phase=armed
  activated_at=0
  expires_at=$(( $(date +%s) + ROLLBACK_SECONDS ))
  write_rollback_helper
  write_state
  arm_rollback_timer
  note "rollback is armed for $ROLLBACK_SECONDS seconds (transaction $transaction)"
  note "activating the already-built candidate without changing the boot target"
  if ! run_bounded "$ACTIVATION_TIMEOUT_SECONDS" "$candidate/bin/switch-to-configuration" test; then
    note "candidate activation command exceeded $ACTIVATION_TIMEOUT_SECONDS seconds; checking runtime readiness"
  fi
  wait_for_candidate_ready "$expires_at" ||
    die "candidate did not become ready before the rollback deadline; rollback remains armed"
  assert_mihomo_config_identity

  activated_at=$(date +%s)
  (( activated_at < expires_at )) || die "candidate became ready after the rollback deadline; rollback remains armed"
  write_state
  note "candidate is active. After $CONFIRM_DELAY_SECONDS seconds and a fresh agent round trip, run:"
  note "  sudo $0 confirm $transaction"
  note "To reject it now, run:"
  note "  sudo $0 rollback $transaction"
}

confirm_candidate() {
  local now
  local requested_transaction=${1:-}

  [[ $# -eq 1 ]] || die "usage: $0 confirm TRANSACTION_ID"
  assert_safe_transaction_id "$requested_transaction"
  acquire_lock
  load_state || die "there is no pending transaction to confirm"
  [[ $requested_transaction == "$transaction" ]] || die "transaction id does not match the pending transaction"
  [[ $phase != rolled-back ]] ||
    die "transaction $transaction was rolled back; rerun rollback to finish cleanup"

  if [[ $phase == armed ]]; then
    timer_is_armed || die "transaction $transaction is no longer armed"
    now=$(date +%s)
    (( now < expires_at )) || die "transaction $transaction has expired; rollback remains armed"
    (( now >= activated_at + CONFIRM_DELAY_SECONDS )) ||
      die "wait at least $CONFIRM_DELAY_SECONDS seconds after activation before confirming"
    [[ $(current_system) == "$candidate" ]] || die "the active system is not this candidate"
    candidate_is_ready || die "candidate runtime is not ready"
    assert_mihomo_config_identity

    note "promoting tested candidate $candidate while rollback remains armed"
    if ! run_bounded "$PROFILE_TIMEOUT_SECONDS" nix-env --profile "$SYSTEM_PROFILE" --set "$candidate" ||
      ! run_bounded "$BOOT_TIMEOUT_SECONDS" "$candidate/bin/switch-to-configuration" boot ||
      [[ $(profile_system) != "$candidate" ]]; then
      die "candidate promotion failed; rollback remains armed"
    fi
    now=$(date +%s)
    (( now < expires_at )) || die "confirmation crossed the rollback deadline; rollback remains armed"
    phase=confirmed
    write_state
  fi

  stop_rollback_units
  clear_state
  note "transaction $transaction confirmed; candidate is persistent and bootable"
}

manual_rollback() {
  local requested_transaction=${1:-}

  [[ $# -eq 1 ]] || die "usage: $0 rollback TRANSACTION_ID"
  assert_safe_transaction_id "$requested_transaction"
  acquire_lock
  load_state || die "there is no pending transaction to roll back"
  [[ $requested_transaction == "$transaction" ]] || die "transaction id does not match the pending transaction"
  if [[ $phase == rolled-back ]]; then
    stop_rollback_units
    clear_state
    note "transaction $transaction rollback cleanup completed"
    return 0
  fi
  [[ $phase == armed ]] || die "transaction $transaction is confirmed; rerun confirm to finish cleanup"

  restore_known_good || die "rollback failed; rollback remains armed"
  phase=rolled-back
  write_state
  stop_rollback_units
  clear_state
  note "transaction $transaction rolled back"
}

show_status() {
  local now
  local remaining

  [[ $# -eq 0 ]] || die "usage: $0 status"
  if ! load_state; then
    note "no guarded Mihomo deployment is pending"
    return 0
  fi

  now=$(date +%s)
  remaining=$((expires_at - now))
  (( remaining >= 0 )) || remaining=0
  printf 'transaction: %s\nphase: %s\nknown_good: %s\ncandidate: %s\nactive_system: %s\npersistent_system: %s\nexpires_at: %s\nremaining_seconds: %s\n' \
    "$transaction" "$phase" "$known_good" "$candidate" "$(current_system)" "$(profile_system)" \
    "$expires_at" "$remaining"
  if timer_is_armed; then
    printf 'rollback_timer: armed (%s)\n' "$timer_unit"
  else
    printf 'rollback_timer: inactive\n'
  fi
  if run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-active --quiet mihomo.service; then
    printf 'mihomo_service: active\n'
  else
    printf 'mihomo_service: inactive\n'
  fi
}

main() {
  local command=${1:-}
  shift || true

  require_root
  for command_name in bash curl date flock git install mktemp nix nix-env readlink rm sha256sum sleep stat systemctl systemd-run timeout; do
    require_command "$command_name"
  done

  case $command in
    switch) switch_candidate "$@" ;;
    status) show_status "$@" ;;
    confirm) confirm_candidate "$@" ;;
    rollback) manual_rollback "$@" ;;
    *) die "usage: $0 {switch|status|confirm TRANSACTION_ID|rollback TRANSACTION_ID}" ;;
  esac
}

main "$@"
