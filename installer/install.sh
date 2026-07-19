#!/usr/bin/env bash
# installer/install.sh
#
# Destructive offline installer for the portable NixOS configuration. Run
# this from a booted NixOS installer environment. It erases one internal
# disk chosen by the operator, partitions it, generates the machine's own
# hardware facts, seeds the approved bootstrap secrets, installs the flake
# fully offline, sets a new login password, and clones the config repo onto
# the target.
#
# Target selection, swap sizing, and the confirmation gate are NOT
# reimplemented here -- they are the tested pure decision functions in
# lib/decisions.sh. This script is the disk-I/O glue around them: it builds
# the device table decisions.sh expects, drives the interactive prompts, and
# performs the actual partition/format/install/copy steps decisions.sh
# deliberately stays free of.
#
# See docs/portable-nixos-usb-installer-spec.md ("Installer (custom
# self-contained offline ISO)" and "Further Notes") for the design this
# implements.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)"

# shellcheck source=./lib/decisions.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/decisions.sh"

# ---------------------------------------------------------------------------
# Config block
# ---------------------------------------------------------------------------

# Hostname written into the generated local.nix. This is the only supported
# target today (the Dynabook X30WK); a future multi-machine installer would
# make this a prompt or CLI argument.
readonly TARGET_HOSTNAME="dynabook-x30wk"

# The account the installed system is built for (see users/andongni.nix).
readonly TARGET_USER="andongni"

# Remote the installed clone's `origin` is pointed at. Adjust this if the
# maintainer's GitHub remote differs.
readonly GITHUB_REMOTE_URL="${GITHUB_REMOTE_URL:-https://github.com/lyh970817/nixos-configuration.git}"

# Directory on the USB stick holding the bootstrap secrets to seed
# (mihomo-config.yaml, credentials.json). Defaults to a `secrets/` directory
# beside the installer/repo on the stick; override for testing.
readonly SECRETS_SOURCE_DIR="${SECRETS_SOURCE_DIR:-$REPO_ROOT/secrets}"

# Flake output to install. `nixos-install --flake` resolves this against the
# baked repo tree carried on the ISO.
readonly FLAKE_REF="${FLAKE_REF:-$REPO_ROOT#system}"

# Where the target filesystem gets mounted during install. Override only for
# loopback/dry-run testing; production installs use the default.
MOUNT_ROOT="${MOUNT_ROOT:-/mnt}"

# Test/dry-run hook: when set, build_device_table() reads this TSV file
# instead of shelling out to lsblk, so the loopback test suite can exercise
# the real decisions.sh-backed selection path against a synthetic table
# (loop devices are TYPE=loop, so they never appear as real installer
# candidates -- this is the only way to drive that path against a loop
# device). Unset in production; the real interactive path always calls
# lsblk.
INSTALL_DEVICE_TABLE_FILE="${INSTALL_DEVICE_TABLE_FILE:-}"

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

log() {
  printf '>> %s\n' "$*" >&2
}

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "must be run as root (the installer partitions disks and calls nixos-install)"
  fi
}

# ---------------------------------------------------------------------------
# Target selection (glue around decisions.sh)
# ---------------------------------------------------------------------------

# build_device_table
#
# Produces the tab-separated NAME/RM/TRAN/TYPE/SIZE/MODEL/SERIAL table
# lib/decisions.sh expects (see installer/README.md). Uses lsblk's `-P`
# key="value" pairs output, which quotes each field individually, so MODEL
# and SERIAL strings containing spaces still parse correctly -- lsblk's
# default columnar output does not have that guarantee.
build_device_table() {
  if [[ -n "$INSTALL_DEVICE_TABLE_FILE" ]]; then
    cat "$INSTALL_DEVICE_TABLE_FILE"
    return
  fi

  local line
  while IFS= read -r line; do
    local NAME="" RM="" TRAN="" TYPE="" SIZE="" MODEL="" SERIAL=""
    eval "$line"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$NAME" "$RM" "$TRAN" "$TYPE" "$SIZE" "$MODEL" "$SERIAL"
  done < <(lsblk -dn -P -o NAME,RM,TRAN,TYPE,SIZE,MODEL,SERIAL)
}

# select_target
#
# Lists the safe candidate disks, prompts the operator to type the exact
# target, and resolves it via decisions.sh. Prints the resolved device path
# to stdout on success; aborts the whole script otherwise. No guessing, no
# default, no retry loop -- an ambiguous or refused answer is a hard stop
# and the operator reruns the script.
select_target() {
  local table candidates typed row device

  table="$(build_device_table)"

  candidates="$(printf '%s\n' "$table" | filter_candidate_disks)"
  if [[ -z "$candidates" ]]; then
    die "no internal (non-removable, non-USB) disks found; refusing to install"
  fi

  log "Candidate internal disks:"
  printf '%s\n' "$candidates" | awk -F'\t' '{ printf "  /dev/%-10s %-8s model=%-20s serial=%s\n", $1, $5, $6, $7 }' >&2

  read -r -p "Type the exact target device (e.g. sda or /dev/sda): " typed

  set +e
  row="$(printf '%s\n' "$table" | resolve_target_device "$typed")"
  local rc=$?
  set -e

  case "$rc" in
    "$DECISIONS_EXIT_OK") ;;
    "$DECISIONS_EXIT_REFUSED")
      die "'$typed' is removable and/or USB-attached; refusing to use it as an install target"
      ;;
    "$DECISIONS_EXIT_AMBIGUOUS")
      die "'$typed' does not uniquely match a listed internal disk; aborting"
      ;;
    *)
      die "target resolution failed unexpectedly (exit $rc)"
      ;;
  esac

  device="/dev/$(printf '%s' "$row" | awk -F'\t' '{ print $1 }')"
  printf '%s\n' "$row" > "$STATE_DIR/resolved-row.tsv"
  printf '%s' "$device"
}

# confirm_target <resolved-device>
#
# Re-prints the resolved disk's model/serial/size and requires the two-part
# typed confirmation from decisions.sh. Aborts on anything but an exact
# match; no default, no timeout-to-yes.
confirm_target() {
  local device="$1" row typed_device typed_word

  row="$(cat "$STATE_DIR/resolved-row.tsv")"
  log "Resolved target: $device"
  printf '%s\n' "$row" | awk -F'\t' -v d="$device" '{ printf "  %s  size=%s  model=%s  serial=%s\n", d, $5, $6, $7 }' >&2
  log "THIS WILL ERASE ALL DATA ON $device."

  read -r -p "Retype the full device path to confirm ($device): " typed_device
  read -r -p "Type ERASE (all caps) to confirm: " typed_word

  if ! confirm_erase "$device" "$typed_device" "$typed_word"; then
    die "confirmation did not match; aborting without touching $device"
  fi
}

# ---------------------------------------------------------------------------
# Partitioning / formatting / mounting
# ---------------------------------------------------------------------------

# partition_suffix <device>
#
# nvme/mmcblk devices need a "p" before the partition number
# (/dev/nvme0n1p1); sd/vd/hd devices don't (/dev/sda1). Distinguish by
# whether the device's base name already ends in a digit.
partition_suffix() {
  local device="$1"
  if [[ "$(basename "$device")" =~ [0-9]$ ]]; then
    printf 'p'
  fi
}

partition_disk() {
  local device="$1" swap_gib="$2" suffix
  suffix="$(partition_suffix "$device")"

  log "Partitioning $device (GPT: ESP 512M, swap ${swap_gib}G, ext4 root rest)..."
  nix shell nixpkgs#gptfdisk --command sgdisk --zap-all "$device" >&2
  nix shell nixpkgs#gptfdisk --command sgdisk \
    -n1:0:+512M -t1:ef00 -c1:ESP \
    -n2:0:+"${swap_gib}"G -t2:8200 -c2:swap \
    -n3:0:0 -t3:8300 -c3:nixos \
    "$device" >&2

  udevadm settle --timeout=10 || true
  partx -u "$device" 2>/dev/null || true
  blockdev --rereadpt "$device" 2>/dev/null || true
  udevadm settle --timeout=10 || true

  ESP_PART="${device}${suffix}1"
  SWAP_PART="${device}${suffix}2"
  ROOT_PART="${device}${suffix}3"
}

format_partitions() {
  log "Formatting $ESP_PART (FAT32 ESP), $SWAP_PART (swap), $ROOT_PART (ext4 root)..."
  mkfs.fat -F32 -n ESP "$ESP_PART" >&2
  mkswap -L nixos-swap "$SWAP_PART" >&2
  mkfs.ext4 -F -L nixos "$ROOT_PART" >&2
}

mount_target() {
  log "Mounting $ROOT_PART at $MOUNT_ROOT, $ESP_PART at $MOUNT_ROOT/boot..."
  mkdir -p "$MOUNT_ROOT"
  mount "$ROOT_PART" "$MOUNT_ROOT"
  mkdir -p "$MOUNT_ROOT/boot"
  mount "$ESP_PART" "$MOUNT_ROOT/boot"
  swapon "$SWAP_PART"
}

# ---------------------------------------------------------------------------
# Facts generation
# ---------------------------------------------------------------------------

generate_facts() {
  log "Generating hardware facts for the mounted target..."
  nixos-generate-config --root "$MOUNT_ROOT" >&2

  cat > "$MOUNT_ROOT/etc/nixos/local.nix" <<EOF
{ networking.hostName = "$TARGET_HOSTNAME"; }
EOF
}

# sync_installer_facts / restore_installer_facts
#
# CRUCIAL (see spec "Further Notes"): configuration.nix imports
# /etc/nixos/hardware-configuration.nix and /etc/nixos/local.nix by
# ABSOLUTE path. `nixos-install --flake ... --impure` evaluates that flake
# with the Nix evaluator running in the *installer's own* root filesystem
# (the chroot into $MOUNT_ROOT only happens later, for bootloader
# installation) -- so those absolute paths resolve against the installer's
# own /etc/nixos, not $MOUNT_ROOT/etc/nixos. Verified by reading
# nixos-install itself: it builds the system profile with plain `nix build`
# before any nixos-enter/chroot call is made. The generated facts must
# therefore also be copied to the installer's own /etc/nixos before the
# build, and cleaned up afterwards so a rerun (or the installer's next boot)
# doesn't inherit stale facts.
INSTALLER_FACTS_SYNCED=0

sync_installer_facts() {
  log "Copying generated facts to the installer's own /etc/nixos for flake eval..."
  mkdir -p /etc/nixos
  cp "$MOUNT_ROOT/etc/nixos/hardware-configuration.nix" /etc/nixos/hardware-configuration.nix
  cp "$MOUNT_ROOT/etc/nixos/local.nix" /etc/nixos/local.nix
  INSTALLER_FACTS_SYNCED=1
}

restore_installer_facts() {
  if [[ "$INSTALLER_FACTS_SYNCED" -eq 1 ]]; then
    rm -f /etc/nixos/hardware-configuration.nix /etc/nixos/local.nix
    INSTALLER_FACTS_SYNCED=0
  fi
}

# ---------------------------------------------------------------------------
# Target user (must exist before secrets can be seeded with correct
# ownership -- see below)
# ---------------------------------------------------------------------------

# create_target_user
#
# Must run AFTER run_nixos_install: nixos-enter chroots using the target's
# own /nix/var/nix/profiles/system/sw/bin/bash, which only exists once
# nixos-install has built and installed the system closure onto
# $MOUNT_ROOT (confirmed empirically -- nixos-enter fails outright against
# an empty, not-yet-installed root).
#
# `nixos-install` only installs the bootloader (`switch-to-configuration
# boot`); it does not run the system activation script, so the declared
# user account does not exist on $MOUNT_ROOT yet and won't until first real
# boot. Secrets and the repo clone need a real uid/gid to be owned by *now*,
# so pre-create the account with plain useradd. This is safe: NixOS's user
# activation keeps the uid/gid of an already-existing account with a
# matching name (it only allocates a fresh id for a brand-new user), so
# first boot's declarative activation adopts this account (fixing up
# shell/groups) rather than recreating it.
create_target_user() {
  if nixos-enter --root "$MOUNT_ROOT" -c "id -u $TARGET_USER" &>/dev/null; then
    log "$TARGET_USER already exists in the target, reusing it"
    return
  fi
  log "Pre-creating $TARGET_USER account so seeded secrets have a real owner..."
  nixos-enter --root "$MOUNT_ROOT" -c "useradd -m -U $TARGET_USER"
}

# target_user_ids
#
# Prints "<uid> <gid>" for TARGET_USER inside the target. Two numbers, not a
# combined "uid:gid" string: `install -o/-g` (unlike `chown`) only accepts a
# single owner or group each, so callers that need install(1) read this
# apart with `read -r uid gid`; callers that want chown(1) can still join it
# back as "$uid:$gid".
target_user_ids() {
  local uid gid
  uid="$(nixos-enter --root "$MOUNT_ROOT" -c "id -u $TARGET_USER")"
  gid="$(nixos-enter --root "$MOUNT_ROOT" -c "id -g $TARGET_USER")"
  printf '%s %s\n' "$uid" "$gid"
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

seed_secrets() {
  local proxy_src="$SECRETS_SOURCE_DIR/mihomo-config.yaml"
  local dictation_src="$SECRETS_SOURCE_DIR/credentials.json"
  local uid gid

  if [[ ! -f "$proxy_src" ]]; then
    die "proxy secret not found at $proxy_src (set SECRETS_SOURCE_DIR)"
  fi
  if [[ ! -f "$dictation_src" ]]; then
    die "dictation credential not found at $dictation_src (set SECRETS_SOURCE_DIR)"
  fi

  log "Seeding proxy secret to $MOUNT_ROOT/etc/nixos/secrets/mihomo-config.yaml..."
  install -d -m 0700 -o root -g root "$MOUNT_ROOT/etc/nixos/secrets"
  install -m 0600 -o root -g root "$proxy_src" "$MOUNT_ROOT/etc/nixos/secrets/mihomo-config.yaml"

  read -r uid gid < <(target_user_ids)
  log "Seeding dictation credential to $MOUNT_ROOT/home/$TARGET_USER/.config/hyprwhspr/credentials.json..."
  install -d -m 0700 -o "$uid" -g "$gid" "$MOUNT_ROOT/home/$TARGET_USER/.config"
  install -d -m 0700 -o "$uid" -g "$gid" "$MOUNT_ROOT/home/$TARGET_USER/.config/hyprwhspr"
  install -m 0600 -o "$uid" -g "$gid" "$dictation_src" \
    "$MOUNT_ROOT/home/$TARGET_USER/.config/hyprwhspr/credentials.json"

  # USB copies are intentionally retained (install(1) copies, never moves).
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

run_nixos_install() {
  log "Running nixos-install --flake $FLAKE_REF --impure, fully offline..."
  # nixos-install has no --offline flag of its own; forcing an empty
  # substituters list is what makes the build refuse the network and rely
  # entirely on the local store (the closure baked into the ISO, per issue
  # 07).
  nixos-install \
    --root "$MOUNT_ROOT" \
    --flake "$FLAKE_REF" \
    --impure \
    --no-root-passwd \
    --no-channel-copy \
    --option substituters ""
}

set_target_password() {
  log "Set a new login password for $TARGET_USER."
  nixos-enter --root "$MOUNT_ROOT" -c "passwd $TARGET_USER"
}

# ---------------------------------------------------------------------------
# Repo clone
# ---------------------------------------------------------------------------

populate_repo_clone() {
  local dest="$MOUNT_ROOT/home/$TARGET_USER/.nixos-config" uid gid

  log "Populating the config repo at $dest..."
  if [ -d "$REPO_ROOT/.git" ]; then
    # Normal case: REPO_ROOT is a real git checkout (e.g. the USB stick).
    git clone "$REPO_ROOT" "$dest" >&2
    git -C "$dest" remote set-url origin "$GITHUB_REMOTE_URL"
  else
    # On the ISO the repo is carried as a plain, read-only store copy via
    # environment.etc."nixos-config".source (no .git), which `git clone`
    # refuses. Copy the tree, make it user-writable, and initialize a fresh
    # repo pointed at origin so later updates are a manual `git pull`.
    mkdir -p "$dest"
    cp -a "$REPO_ROOT/." "$dest/"
    chmod -R u+w "$dest"
    git -C "$dest" init -q
    git -C "$dest" remote add origin "$GITHUB_REMOTE_URL"
  fi

  read -r uid gid < <(target_user_ids)
  chown -R "$uid:$gid" "$dest"
}

# ---------------------------------------------------------------------------
# First boot
# ---------------------------------------------------------------------------

write_first_boot_notice() {
  local uid gid notice="$MOUNT_ROOT/home/$TARGET_USER/FIRST-BOOT.md"

  cat > "$notice" <<'EOF'
# First boot

No Tailscale identity was copied from the source machine. Run this once,
as yourself, to join the tailnet as a new node:

    tailscale up

That is the only interactive task left after install.
EOF
  read -r uid gid < <(target_user_ids)
  chown "$uid:$gid" "$notice"
  chmod 0644 "$notice"
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

cleanup() {
  restore_installer_facts
  swapoff "$SWAP_PART" 2>/dev/null || true
  umount -R "$MOUNT_ROOT" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  require_root

  STATE_DIR="$(mktemp -d)"
  trap 'rm -rf "$STATE_DIR"; cleanup' EXIT

  local ram_kib swap_gib device

  device="$(select_target)"
  confirm_target "$device"

  ram_kib="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"
  swap_gib="$(swap_size_from_ram_kib "$ram_kib")"

  partition_disk "$device" "$swap_gib"
  format_partitions
  mount_target

  generate_facts
  sync_installer_facts

  run_nixos_install

  create_target_user
  seed_secrets

  set_target_password
  populate_repo_clone
  write_first_boot_notice

  log "Install complete. Reboot into $TARGET_HOSTNAME, then run: tailscale up"
}

main "$@"
