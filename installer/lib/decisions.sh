#!/usr/bin/env bash
# installer/lib/decisions.sh
#
# Pure decision functions for the portable-NixOS installer's target
# selection, sizing, and confirmation logic. Every function here reads its
# inputs from arguments and/or stdin and reports its outcome via stdout and
# exit code only. Nothing in this file touches a real block device, runs
# sfdisk/mkfs/dd, or has any other side effect, so it is always safe to
# `source` this file -- including from unit tests.
#
# See installer/README.md for the exact input table format, the contract of
# each function below, and how to run the test suite.

set -uo pipefail

# Exit codes shared by the functions below. Callers (including tests) should
# assert on these constants, not on raw numbers.
readonly DECISIONS_EXIT_OK=0
readonly DECISIONS_EXIT_FAIL=1
readonly DECISIONS_EXIT_REFUSED=2
readonly DECISIONS_EXIT_AMBIGUOUS=3

# filter_candidate_disks
#
# Reads a device table on stdin (see README.md for the exact TSV format:
# NAME, RM, TRAN, TYPE, SIZE, MODEL, SERIAL) and writes to stdout only the
# rows that are safe installer targets: whole disks (TYPE=disk) that are
# non-removable (RM=0) and not attached over USB (TRAN != usb). Always
# exits 0; an empty result (no candidates) is a valid, non-error outcome.
filter_candidate_disks() {
  awk -F'\t' '
    $4 == "disk" && $2 == "0" && tolower($3) != "usb" { print }
  '
}

# resolve_target_device <typed-device>
#
# Given the operator-typed device string (accepts either a bare name such
# as "sda" or a full path such as "/dev/sda") and the FULL, unfiltered
# device table on stdin, resolves it to exactly one internal disk.
#
# Exit codes:
#   DECISIONS_EXIT_OK        - unique match among internal disks; the
#                               matching table row is printed to stdout.
#   DECISIONS_EXIT_REFUSED   - the typed name identifies a real device, but
#                               it is removable and/or USB-attached.
#   DECISIONS_EXIT_AMBIGUOUS - the typed name matches zero, or more than
#                               one, internal disk (no-match and ambiguous
#                               match are both reported this way; either
#                               way the caller must not proceed).
resolve_target_device() {
  local typed="$1"
  local name="${typed#/dev/}"

  local table
  table="$(cat)"

  local candidates
  candidates="$(printf '%s\n' "$table" | filter_candidate_disks)"

  local candidate_matches
  candidate_matches="$(printf '%s\n' "$candidates" | awk -F'\t' -v n="$name" '$1 == n { c++ } END { print c + 0 }')"

  if [[ "$candidate_matches" -eq 1 ]]; then
    printf '%s\n' "$candidates" | awk -F'\t' -v n="$name" '$1 == n'
    return "$DECISIONS_EXIT_OK"
  fi

  if [[ "$candidate_matches" -eq 0 ]]; then
    local full_matches
    full_matches="$(printf '%s\n' "$table" | awk -F'\t' -v n="$name" '$1 == n { c++ } END { print c + 0 }')"
    if [[ "$full_matches" -ge 1 ]]; then
      # The name is real but was filtered out: removable and/or USB.
      return "$DECISIONS_EXIT_REFUSED"
    fi
    return "$DECISIONS_EXIT_AMBIGUOUS"
  fi

  # candidate_matches > 1: the table listed the same disk name twice.
  return "$DECISIONS_EXIT_AMBIGUOUS"
}

# swap_size_from_ram_kib <ram-kib>
#
# Given total RAM in KiB (the unit /proc/meminfo's MemTotal is already in),
# computes the hibernate-sized swap partition as a whole number of GiB,
# rounded UP so swap is never smaller than RAM. Prints the GiB count (a
# bare integer, e.g. "16") to stdout on success.
#
# Exit codes:
#   DECISIONS_EXIT_OK   - printed a valid GiB count.
#   DECISIONS_EXIT_FAIL - input was not a positive integer.
swap_size_from_ram_kib() {
  local ram_kib="$1"

  if ! [[ "$ram_kib" =~ ^[0-9]+$ ]] || [[ "$ram_kib" -le 0 ]]; then
    return "$DECISIONS_EXIT_FAIL"
  fi

  local kib_per_gib=$((1024 * 1024))
  local gib=$(( (ram_kib + kib_per_gib - 1) / kib_per_gib ))
  printf '%s\n' "$gib"
  return "$DECISIONS_EXIT_OK"
}

# confirm_erase <resolved-device> <typed-device> <typed-word>
#
# Two-part confirmation gate. Succeeds only if <typed-device> is exactly
# equal to <resolved-device> AND <typed-word> is exactly the literal
# string "ERASE" (case-sensitive, no surrounding text).
#
# Exit codes:
#   DECISIONS_EXIT_OK   - both parts matched exactly; proceed.
#   DECISIONS_EXIT_FAIL - either part did not match; do not proceed.
confirm_erase() {
  local resolved_device="$1"
  local typed_device="$2"
  local typed_word="$3"

  if [[ "$typed_device" == "$resolved_device" && "$typed_word" == "ERASE" ]]; then
    return "$DECISIONS_EXIT_OK"
  fi

  return "$DECISIONS_EXIT_FAIL"
}

# Guard: only runs when this file is executed directly (e.g. `./decisions.sh
# resolve_target_device sda < table.tsv`), never when sourced by the
# installer script or by the test suite. This is what makes it safe to
# `source` this file from bats without triggering anything.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main() {
    local fn="$1"
    shift
    "$fn" "$@"
  }
  main "$@"
fi
