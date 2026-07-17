#!/usr/bin/env bats
# installer/tests/decisions.bats
#
# Unit tests for installer/lib/decisions.sh. These assert external
# behaviour only -- given inputs, what decision/exit code comes out -- so
# they keep passing across refactors of the library's internals. See
# installer/README.md for the input table format and function contracts.

setup() {
  local lib_dir
  lib_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib"
  # shellcheck disable=SC1090,SC1091
  source "$lib_dir/decisions.sh"

  # A representative lsblk-shaped device table (see README.md for the
  # column order): a USB stick, a removable non-USB reader, two internal
  # disks, one partition, one loop device, and one optical drive. Fields
  # are tab-separated; build with printf so real tabs land in the file.
  TABLE="$(
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      sda 0 usb disk 57.3G Cruzer USBSERIAL1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      sdb 1 sata disk 59.5G SD_Reader SDSERIAL1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      nvme0n1 0 nvme disk 476.9G SAMSUNG_MZVL2512 NVMESERIAL1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      sdc 0 sata disk 931.5G ST1000DM010 SATASERIAL1
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      nvme0n1p1 0 nvme part 512M - -
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      loop0 0 "" loop 100M - -
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      sr0 1 ata rom 1024M - -
  )"

  # A malformed table used only to exercise the true "more than one match"
  # branch of resolve_target_device: two internal-disk rows sharing a name.
  DUPLICATE_TABLE="$(
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sda 0 sata disk 500G ModelA SerialA
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' sda 0 sata disk 500G ModelB SerialB
  )"
}

# --- filter_candidate_disks ---------------------------------------------

@test "filter_candidate_disks keeps only non-removable, non-USB whole disks" {
  run filter_candidate_disks <<< "$TABLE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nvme0n1"* ]]
  [[ "$output" == *"sdc"* ]]
}

@test "filter_candidate_disks excludes the USB stick" {
  run filter_candidate_disks <<< "$TABLE"
  [[ "$output" != *"USBSERIAL1"* ]]
}

@test "filter_candidate_disks excludes the removable non-USB reader" {
  run filter_candidate_disks <<< "$TABLE"
  [[ "$output" != *"SDSERIAL1"* ]]
}

@test "filter_candidate_disks excludes partitions, loop devices, and optical drives" {
  run filter_candidate_disks <<< "$TABLE"
  [[ "$output" != *"nvme0n1p1"* ]]
  [[ "$output" != *"loop0"* ]]
  [[ "$output" != *"sr0"* ]]
}

# --- resolve_target_device -----------------------------------------------

@test "resolve_target_device accepts a bare name that uniquely matches an internal disk" {
  run resolve_target_device "sdc" <<< "$TABLE"
  [ "$status" -eq "$DECISIONS_EXIT_OK" ]
  [[ "$output" == *"sdc"* ]]
  [[ "$output" == *"SATASERIAL1"* ]]
}

@test "resolve_target_device accepts a full /dev path that uniquely matches an internal disk" {
  run resolve_target_device "/dev/nvme0n1" <<< "$TABLE"
  [ "$status" -eq "$DECISIONS_EXIT_OK" ]
  [[ "$output" == *"nvme0n1"* ]]
}

@test "resolve_target_device refuses a USB target" {
  run resolve_target_device "sda" <<< "$TABLE"
  [ "$status" -eq "$DECISIONS_EXIT_REFUSED" ]
}

@test "resolve_target_device refuses a removable non-USB target" {
  run resolve_target_device "sdb" <<< "$TABLE"
  [ "$status" -eq "$DECISIONS_EXIT_REFUSED" ]
}

@test "resolve_target_device aborts on no match" {
  run resolve_target_device "sdz" <<< "$TABLE"
  [ "$status" -eq "$DECISIONS_EXIT_AMBIGUOUS" ]
}

@test "resolve_target_device aborts on ambiguous match" {
  run resolve_target_device "sda" <<< "$DUPLICATE_TABLE"
  [ "$status" -eq "$DECISIONS_EXIT_AMBIGUOUS" ]
}

@test "resolve_target_device refuse and ambiguous exit codes are distinct" {
  [ "$DECISIONS_EXIT_REFUSED" -ne "$DECISIONS_EXIT_AMBIGUOUS" ]
}

# --- swap_size_from_ram_kib -----------------------------------------------

@test "swap_size_from_ram_kib computes an exact whole-GiB size" {
  run swap_size_from_ram_kib 16777216 # exactly 16 GiB
  [ "$status" -eq "$DECISIONS_EXIT_OK" ]
  [ "$output" -eq 16 ]
}

@test "swap_size_from_ram_kib rounds a non-whole-GiB size up" {
  run swap_size_from_ram_kib 8500000 # a bit over 8 GiB
  [ "$status" -eq "$DECISIONS_EXIT_OK" ]
  [ "$output" -eq 9 ]
}

@test "swap_size_from_ram_kib rounds a small size up to at least 1 GiB" {
  run swap_size_from_ram_kib 1
  [ "$status" -eq "$DECISIONS_EXIT_OK" ]
  [ "$output" -eq 1 ]
}

@test "swap_size_from_ram_kib rejects non-numeric input" {
  run swap_size_from_ram_kib "lots"
  [ "$status" -eq "$DECISIONS_EXIT_FAIL" ]
}

@test "swap_size_from_ram_kib rejects zero" {
  run swap_size_from_ram_kib 0
  [ "$status" -eq "$DECISIONS_EXIT_FAIL" ]
}

# --- confirm_erase ---------------------------------------------------------

@test "confirm_erase accepts the exact device path and the literal word ERASE" {
  run confirm_erase "/dev/sdc" "/dev/sdc" "ERASE"
  [ "$status" -eq "$DECISIONS_EXIT_OK" ]
}

@test "confirm_erase rejects a mistyped device path" {
  run confirm_erase "/dev/sdc" "/dev/sdb" "ERASE"
  [ "$status" -eq "$DECISIONS_EXIT_FAIL" ]
}

@test "confirm_erase rejects lowercase erase" {
  run confirm_erase "/dev/sdc" "/dev/sdc" "erase"
  [ "$status" -eq "$DECISIONS_EXIT_FAIL" ]
}

@test "confirm_erase rejects a missing second word" {
  run confirm_erase "/dev/sdc" "/dev/sdc" ""
  [ "$status" -eq "$DECISIONS_EXIT_FAIL" ]
}

@test "confirm_erase rejects extra text around ERASE" {
  run confirm_erase "/dev/sdc" "/dev/sdc" "ERASE please"
  [ "$status" -eq "$DECISIONS_EXIT_FAIL" ]
}
