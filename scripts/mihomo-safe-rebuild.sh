#!/usr/bin/env bash
# Safely test a NixOS generation that changes Mihomo without making it bootable
# until it has been explicitly confirmed from a fresh agent connection.
set -euo pipefail

readonly REPO_DIR="/home/andongni/Yandex.Disk/System/nixos-configuration"
readonly MIHOMO_CONFIG="mihomo-config.yaml"
readonly MIHOMO_IDENTITY="mihomo-config.sha256"
readonly MIHOMO_MODULE="modules/services/mihomo.nix"
readonly STATE_DIR="/var/lib/mihomo-safe-rebuild"
readonly STATE_FILE="$STATE_DIR/current.env"
readonly HISTORY_DIR="$STATE_DIR/history"
readonly EVENT_LOG="$STATE_DIR/events.log"
readonly LOCK_FILE="/run/lock/mihomo-safe-rebuild.lock"
readonly SYSTEM_PROFILE="/nix/var/nix/profiles/system"
readonly TIMER_PREFIX="mihomo-safe-rebuild-rollback"
readonly CONFIRM_DELAY_SECONDS=20
readonly BUILD_TIMEOUT_SECONDS=3600
readonly ACTIVATION_TIMEOUT_SECONDS=90
readonly PROFILE_TIMEOUT_SECONDS=15
readonly BOOT_TIMEOUT_SECONDS=30
readonly SYSTEMCTL_TIMEOUT_SECONDS=15
readonly ROLLBACK_ATTEMPTS=3
readonly ROLLBACK_RETRY_SECONDS=10

transaction=""
known_good=""
candidate=""
created_at=0
activated_at=0
expires_at=0
phase=""
attempt=0

die() {
  printf 'mihomo-safe-rebuild: %s\n' "$*" >&2
  record_event "ERROR: $*"
  exit 1
}

note() {
  printf 'mihomo-safe-rebuild: %s\n' "$*"
  record_event "$*"
}

record_event() {
  local event_transaction=${transaction:--}

  (( EUID == 0 )) || return 0
  install -d -m 0700 -o root -g root "$STATE_DIR" "$HISTORY_DIR" 2>/dev/null || return 0
  touch "$EVENT_LOG" 2>/dev/null || return 0
  chmod 0600 "$EVENT_LOG" 2>/dev/null || return 0
  printf '%s transaction=%s %s\n' "$(date --iso-8601=seconds)" "$event_transaction" "$*" >>"$EVENT_LOG" || return 0
  sync -f "$EVENT_LOG" 2>/dev/null || true
}

require_root() {
  [[ $EUID -eq 0 ]] || die "run this command with sudo"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"
}

current_system() {
  readlink -f /run/current-system
}

profile_system() {
  readlink -f "$SYSTEM_PROFILE"
}

timer_unit() {
  printf '%s@%s.timer\n' "$TIMER_PREFIX" "$1"
}

timer_deadline_epoch() {
  local found_next=""
  local found_unit=""
  local json
  local matched
  local next_count=0
  local next_pattern='"next"[[:space:]]*:[[:space:]]*([0-9]+)'
  local next_usec
  local remainder
  local requested_unit=$1
  local unit_count=0
  local unit_pattern='"unit"[[:space:]]*:[[:space:]]*"([^"]+)"'

  json=$(run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl list-timers \
    "$requested_unit" --no-pager --output=json) || return 1
  [[ $json == \[*\] ]] || return 1

  remainder=$json
  while [[ $remainder =~ $unit_pattern ]]; do
    matched=${BASH_REMATCH[0]}
    found_unit=${BASH_REMATCH[1]}
    unit_count=$((unit_count + 1))
    remainder=${remainder#*"$matched"}
  done

  remainder=$json
  while [[ $remainder =~ $next_pattern ]]; do
    matched=${BASH_REMATCH[0]}
    found_next=${BASH_REMATCH[1]}
    next_count=$((next_count + 1))
    remainder=${remainder#*"$matched"}
  done

  (( unit_count == 1 && next_count == 1 )) || return 1
  [[ $found_unit == "$requested_unit" && $found_next =~ ^[0-9]+$ ]] || return 1
  next_usec=$found_next
  (( next_usec > 0 )) || return 1
  printf '%s\n' "$((next_usec / 1000000))"
}

run_bounded() {
  local seconds=$1
  shift
  timeout --kill-after=10s "${seconds}s" "$@"
}

assert_safe_transaction_id() {
  [[ $1 =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid transaction id"
}

prepare_state_dir() {
  install -d -m 0700 -o root -g root "$STATE_DIR" "$HISTORY_DIR"
}

load_state() {
  [[ -f "$STATE_FILE" ]] || return 1
  [[ -O "$STATE_FILE" ]] || die "transaction state is not root-owned"
  [[ ! -L "$STATE_FILE" ]] || die "transaction state must not be a symlink"
  [[ $(stat -c '%a' "$STATE_FILE") == 600 ]] || die "transaction state must have mode 0600"

  unset transaction known_good candidate created_at activated_at expires_at phase attempt
  # The file is created only by write_state below, is root-owned, and is mode 0600.
  # shellcheck disable=SC1090
  source "$STATE_FILE"

  [[ ${transaction:-} =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid transaction state"
  [[ ${known_good:-} == /nix/store/* ]] || die "invalid known-good closure in state"
  [[ ${candidate:-} == /nix/store/* ]] || die "invalid candidate closure in state"
  [[ ${created_at:-} =~ ^[0-9]+$ ]] || die "invalid creation time in state"
  [[ ${activated_at:-} =~ ^[0-9]+$ ]] || die "invalid activation time in state"
  [[ ${expires_at:-} =~ ^[0-9]+$ ]] || die "invalid expiration time in state"
  [[ ${attempt:-} =~ ^[0-9]+$ ]] || die "invalid attempt count in state"
  case ${phase:-} in
    prepared|armed|active|activation-failed|confirming|rollback-attempt|rollback-failed|rolled-back|confirmed) ;;
    *) die "invalid transaction phase in state" ;;
  esac
}

write_state() {
  local next_phase=$1
  local next_attempt=${2:-$attempt}
  local temporary

  prepare_state_dir
  temporary=$(mktemp "$STATE_DIR/.current.env.XXXXXX")
  chmod 0600 "$temporary"
  {
    printf 'transaction=%q\n' "$transaction"
    printf 'known_good=%q\n' "$known_good"
    printf 'candidate=%q\n' "$candidate"
    printf 'created_at=%q\n' "$created_at"
    printf 'activated_at=%q\n' "$activated_at"
    printf 'expires_at=%q\n' "$expires_at"
    printf 'phase=%q\n' "$next_phase"
    printf 'attempt=%q\n' "$next_attempt"
  } >"$temporary"
  sync -f "$temporary"
  mv -f "$temporary" "$STATE_FILE"
  sync -f "$STATE_DIR"
  phase=$next_phase
  attempt=$next_attempt
  record_event "phase=$phase attempt=$attempt"
}

clear_state() {
  record_event "clearing transaction state from phase=$phase"
  rm -f "$STATE_FILE"
  sync -f "$STATE_DIR"
}

archive_state() {
  local archive
  local outcome=$1

  [[ $outcome =~ ^[a-z-]+$ ]] || die "internal error: invalid archive outcome"
  archive="$HISTORY_DIR/${outcome}-${transaction}-$(date -u +%Y%m%dT%H%M%SZ).env"
  cp --preserve=mode,ownership,timestamps "$STATE_FILE" "$archive"
  sync -f "$archive"
  sync -f "$HISTORY_DIR"
  note "transaction state archived at $archive"
}

archive_failed_state() {
  archive_state failed
  note "rollback failed; durable state remains available for boot recovery"
}

acquire_transaction_lock() {
  install -d -m 0755 -o root -g root "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  case $1 in
    reject)
      flock -n 9 || die "another Mihomo safe-rebuild transaction command is running"
      ;;
    wait)
      flock 9
      ;;
    *)
      die "internal error: unknown lock mode $1"
      ;;
  esac
}

assert_guard_infrastructure_installed() {
  local unit

  for unit in \
    "${TIMER_PREFIX}@.timer" \
    "${TIMER_PREFIX}@.service" \
    "mihomo-safe-rebuild-boot-recovery.service"; do
    run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl cat "$unit" >/dev/null ||
      die "guard infrastructure is not installed: $unit"
  done
  run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-enabled --quiet mihomo-safe-rebuild-boot-recovery.service ||
    die "boot recovery is not enabled; install the guard infrastructure first"
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
      "$MIHOMO_IDENTITY"|"$MIHOMO_MODULE")
        saw_mihomo=1
        ;;
      *)
        die "HEAD is not a dedicated Mihomo commit; it also changes $changed"
        ;;
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
  (( ${#identity_lines[@]} == 1 )) || die "$MIHOMO_IDENTITY must contain exactly one SHA-256 hash"
  expected=${identity_lines[0]}
  [[ $expected =~ ^[0-9a-f]{64}$ ]] || die "$MIHOMO_IDENTITY does not contain a valid lowercase SHA-256 hash"
  actual=$(sha256sum -- "$REPO_DIR/$MIHOMO_CONFIG")
  actual=${actual%% *}
  [[ $actual == "$expected" ]] ||
    die "$MIHOMO_CONFIG does not match $MIHOMO_IDENTITY; update and commit the identity file"
}

build_candidate() {
  note "building the candidate system closure before arming rollback"
  candidate=$(run_bounded "$BUILD_TIMEOUT_SECONDS" nix build --no-link --print-out-paths \
    "$REPO_DIR#nixosConfigurations.andongni.config.system.build.toplevel" --impure)
  [[ $candidate == /nix/store/* ]] || die "Nix did not return a system closure"
  [[ -x "$candidate/bin/switch-to-configuration" ]] || die "candidate is not a NixOS system closure: $candidate"
}

assert_active_candidate() {
  [[ $(current_system) == "$candidate" ]] || die "the active system is not this transaction's candidate"
  run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-active --quiet mihomo.service ||
    die "mihomo.service is not active"
}

restore_known_good_once() {
  local result=0

  note "restoring known-good closure $known_good"
  if [[ $(profile_system) != "$known_good" ]]; then
    run_bounded "$PROFILE_TIMEOUT_SECONDS" nix-env --profile "$SYSTEM_PROFILE" --set "$known_good" || result=1
  fi
  run_bounded "$BOOT_TIMEOUT_SECONDS" "$known_good/bin/switch-to-configuration" boot || result=1
  if [[ $(current_system) != "$known_good" ]]; then
    run_bounded "$ACTIVATION_TIMEOUT_SECONDS" "$known_good/bin/switch-to-configuration" test || result=1
  else
    note "known-good closure is already active; skipping live activation"
  fi

  [[ $(current_system) == "$known_good" ]] || result=1
  [[ $(profile_system) == "$known_good" ]] || result=1
  return "$result"
}

perform_rollback() {
  local number
  local unit

  unit=$(timer_unit "$transaction")
  run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl stop "$unit" 2>/dev/null || true

  for number in $(seq 1 "$ROLLBACK_ATTEMPTS"); do
    write_state rollback-attempt "$number"
    note "rollback attempt $number of $ROLLBACK_ATTEMPTS"
    if restore_known_good_once; then
      write_state rolled-back "$number"
      archive_state rolled-back
      note "rollback completed; known-good closure is active and bootable"
      clear_state
      return 0
    fi
    note "rollback attempt $number failed"
    if (( number < ROLLBACK_ATTEMPTS )); then
      sleep "$ROLLBACK_RETRY_SECONDS"
    fi
  done

  write_state rollback-failed "$ROLLBACK_ATTEMPTS"
  archive_failed_state
  return 1
}

switch_candidate() {
  local unit

  [[ $# -eq 0 ]] || die "usage: $0 switch"
  acquire_transaction_lock reject
  if load_state; then
    die "transaction $transaction is already pending (phase: $phase)"
  fi
  assert_guard_infrastructure_installed
  assert_dedicated_mihomo_commit
  assert_mihomo_config_identity
  build_candidate
  # Detect a local YAML change during the build before any rollback state or
  # timer exists. The pre-build check also ensures both sides of the build saw
  # the same committed identity without logging configuration contents.
  assert_mihomo_config_identity

  known_good=$(profile_system)
  [[ $(current_system) == "$known_good" ]] || die "active system differs from persistent system profile; recover that state before starting a guarded deployment"
  [[ -x "$known_good/bin/switch-to-configuration" ]] || die "persistent system profile is not a NixOS closure"

  transaction="$(date -u +%Y%m%dT%H%M%SZ)-$(od -An -N4 -tx4 /dev/urandom | tr -d ' ')"
  created_at=$(date +%s)
  activated_at=0
  expires_at=0
  attempt=0
  write_state prepared

  unit=$(timer_unit "$transaction")
  write_state armed
  if ! run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl start "$unit" ||
    ! run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-active --quiet "$unit"; then
    run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl stop "$unit" 2>/dev/null || true
    clear_state
    die "could not arm $unit; candidate was not activated"
  fi

  if ! expires_at=$(timer_deadline_epoch "$unit"); then
    run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl stop "$unit" 2>/dev/null || true
    clear_state
    die "could not read the deadline from $unit; candidate was not activated"
  fi
  write_state armed

  note "rollback is armed for transaction $transaction until $(date -d "@$expires_at" --iso-8601=seconds)"
  note "activating the already-built candidate without changing the system profile or boot target"
  if ! run_bounded "$ACTIVATION_TIMEOUT_SECONDS" "$candidate/bin/switch-to-configuration" test; then
    write_state activation-failed
    die "candidate activation failed; rollback remains armed"
  fi

  if [[ $(current_system) != "$candidate" ]]; then
    write_state activation-failed
    die "candidate activation did not become /run/current-system; rollback remains armed"
  fi

  activated_at=$(date +%s)
  write_state active
  note "candidate is active. Wait at least $CONFIRM_DELAY_SECONDS seconds, reconnect through the agent, then run:"
  note "  sudo $0 status"
  note "  sudo $0 confirm $transaction"
  note "To reject it explicitly, run:"
  note "  sudo $0 rollback $transaction"
}

confirm_candidate() {
  local live_expires_at
  local now
  local requested_transaction=${1:-}
  local unit

  [[ $# -eq 1 ]] || die "usage: $0 confirm TRANSACTION_ID"
  assert_safe_transaction_id "$requested_transaction"
  acquire_transaction_lock reject
  load_state || die "there is no pending transaction to confirm"
  [[ $requested_transaction == "$transaction" ]] || die "transaction id does not match the pending transaction"
  [[ $phase == active ]] || die "transaction $transaction is not confirmable (phase: $phase)"

  now=$(date +%s)
  unit=$(timer_unit "$transaction")
  run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-active --quiet "$unit" || die "transaction $transaction is no longer armed"
  live_expires_at=$(timer_deadline_epoch "$unit") || die "could not read the authoritative deadline for transaction $transaction"
  (( now < live_expires_at )) || die "transaction $transaction has expired"
  (( now >= activated_at + CONFIRM_DELAY_SECONDS )) || die "wait at least $CONFIRM_DELAY_SECONDS seconds after activation before confirming"
  assert_active_candidate

  # Keep the rollback timer armed through the promotion. If anything below
  # fails, the rollback path restores both the runtime and persistent target.
  write_state confirming
  note "promoting candidate $candidate to the persistent system profile and boot target"
  if ! run_bounded "$PROFILE_TIMEOUT_SECONDS" nix-env --profile "$SYSTEM_PROFILE" --set "$candidate"; then
    note "profile promotion failed; rolling back immediately"
    perform_rollback || true
    die "candidate promotion failed"
  fi
  if ! run_bounded "$BOOT_TIMEOUT_SECONDS" "$candidate/bin/switch-to-configuration" boot; then
    note "boot-target promotion failed; rolling back immediately"
    perform_rollback || true
    die "candidate boot-target promotion failed"
  fi
  if [[ $(profile_system) != "$candidate" ]]; then
    note "profile does not point to the candidate after promotion; rolling back immediately"
    perform_rollback || true
    die "candidate profile promotion did not persist"
  fi

  now=$(date +%s)
  if ! live_expires_at=$(timer_deadline_epoch "$unit") || (( now >= live_expires_at )); then
    note "confirmation crossed the fixed deadline; rolling back immediately"
    perform_rollback || true
    die "candidate was not confirmed before the deadline"
  fi

  write_state confirmed
  if ! run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl stop "$unit"; then
    note "could not disarm $unit after promotion; rolling back immediately"
    perform_rollback || true
    die "candidate was promoted but rollback could not be disarmed"
  fi
  clear_state
  note "transaction $transaction confirmed; candidate is persistent and bootable"
}

manual_rollback() {
  local requested_transaction=${1:-}

  [[ $# -eq 1 ]] || die "usage: $0 rollback TRANSACTION_ID"
  assert_safe_transaction_id "$requested_transaction"
  acquire_transaction_lock reject
  load_state || die "there is no pending transaction to roll back"
  [[ $requested_transaction == "$transaction" ]] || die "transaction id does not match the pending transaction"
  perform_rollback || die "rollback failed; state and journal logs were preserved for boot recovery"
}

rollback_from_timer() {
  local expected_transaction=${1:-}

  [[ $# -eq 1 ]] || die "internal usage: $0 rollback-from-timer TRANSACTION"
  assert_safe_transaction_id "$expected_transaction"
  acquire_transaction_lock wait
  if ! load_state; then
    note "timer $expected_transaction found no pending transaction"
    return 0
  fi
  if [[ $transaction != "$expected_transaction" ]]; then
    note "timer $expected_transaction does not own pending transaction $transaction"
    return 0
  fi
  if [[ $phase == confirmed || $phase == rolled-back ]]; then
    note "transaction $transaction was already finalized (phase: $phase)"
    clear_state
    return 0
  fi
  note "fixed rollback deadline expired for transaction $transaction"
  perform_rollback || die "automatic rollback failed; boot recovery will retry"
}

boot_recovery() {
  [[ $# -eq 0 ]] || die "internal usage: $0 boot-recovery"
  acquire_transaction_lock wait
  if ! load_state; then
    return 0
  fi
  if [[ $phase == confirmed || $phase == rolled-back ]]; then
    note "removing completed transaction record $transaction (phase: $phase)"
    clear_state
    return 0
  fi
  note "boot found pending transaction $transaction (phase: $phase); restoring known-good closure"
  perform_rollback || die "boot recovery failed; preserved state will be retried at the next boot"
}

show_status() {
  local deadline_display
  local expires_display
  local live_expires_at
  local now
  local remaining
  local unit

  [[ $# -eq 0 ]] || die "usage: $0 status"
  if ! load_state; then
    note "no pending transaction"
    return 0
  fi
  unit=$(timer_unit "$transaction")
  now=$(date +%s)
  if (( expires_at > 0 )); then
    expires_display=$(date -d "@$expires_at" --iso-8601=seconds)
    remaining=$((expires_at - now))
    (( remaining >= 0 )) || remaining=0
  else
    expires_display="pending timer activation"
    remaining="unknown"
  fi
  deadline_display=$expires_display
  case $phase in
    armed|active|activation-failed|confirming)
      run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-active --quiet "$unit" ||
        die "pending transaction $transaction has no active rollback timer"
      live_expires_at=$(timer_deadline_epoch "$unit") ||
        die "could not read the authoritative deadline for transaction $transaction"
      (( now < live_expires_at )) || die "transaction $transaction has expired"
      deadline_display=$(date -d "@$live_expires_at" --iso-8601=seconds)
      remaining=$((live_expires_at - now))
      ;;
  esac
  printf 'transaction: %s\nphase: %s\nknown_good: %s\ncandidate: %s\ncreated_at: %s\nactivated_at: %s\nstored_deadline: %s\ndeadline: %s\nremaining_seconds: %s\nattempt: %s\nevent_log: %s\n' \
    "$transaction" "$phase" "$known_good" "$candidate" "$created_at" "$activated_at" \
    "$expires_display" "$deadline_display" "$remaining" "$attempt" "$EVENT_LOG"
  printf 'active_system: %s\npersistent_system: %s\n' "$(current_system)" "$(profile_system)"
  if run_bounded "$SYSTEMCTL_TIMEOUT_SECONDS" systemctl is-active --quiet "$unit"; then
    printf 'rollback_timer: armed (%s)\n' "$unit"
  else
    printf 'rollback_timer: inactive (%s)\n' "$unit"
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
  require_command nix
  require_command nix-env
  require_command systemctl
  require_command timeout
  require_command flock
  require_command sha256sum

  case $command in
    switch) switch_candidate "$@" ;;
    status) show_status "$@" ;;
    confirm) confirm_candidate "$@" ;;
    rollback) manual_rollback "$@" ;;
    rollback-from-timer) rollback_from_timer "$@" ;;
    boot-recovery) boot_recovery "$@" ;;
    *)
      die "usage: $0 {switch|status|confirm TRANSACTION_ID|rollback TRANSACTION_ID}"
      ;;
  esac
}

main "$@"
