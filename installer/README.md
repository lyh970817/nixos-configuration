# Installer decision logic

This directory holds the portable-NixOS installer's **decision logic**: the
pure, sourceable shell functions that decide which disk to install onto, how
big swap should be, and whether the operator has confirmed the erase. It is
the installer's single automated test seam (see
`docs/portable-nixos-usb-installer-spec.md`, "Testing Decisions"); the
destructive installer script itself (partitioning, `nixos-install`, etc.) is
not part of this directory and is not covered by tests.

- `lib/decisions.sh` -- the decision functions. Safe to `source`: it has no
  side effects and never touches a real device. The only code that runs on
  execution (as opposed to sourcing) is a tiny CLI dispatcher guarded by
  `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`.
- `tests/decisions.bats` -- bats tests that source the library and assert on
  its external behaviour (stdout + exit code) for representative inputs.
- `install.sh` -- the destructive installer itself. Sources `lib/decisions.sh`
  for target selection, swap sizing, and the erase confirmation, then does
  the actual partition/format/mount/`nixos-install` work those functions
  deliberately stay free of. Not part of the automated test seam above; it
  takes `MOUNT_ROOT`, `INSTALL_DEVICE_TABLE_FILE`, `SECRETS_SOURCE_DIR`,
  `FLAKE_REF`, and `GITHUB_REMOTE_URL` environment overrides so it can be
  driven against a loopback disk for manual verification (see the top-of-file
  config block for defaults).

## Device table input format

`filter_candidate_disks` and `resolve_target_device` both read a device
table on stdin. One line per block device, seven **tab-separated** fields,
in this order:

```
NAME	RM	TRAN	TYPE	SIZE	MODEL	SERIAL
```

| Field  | Meaning                                                        |
|--------|-----------------------------------------------------------------|
| NAME   | Device name without the `/dev/` prefix, e.g. `sda`, `nvme0n1`.  |
| RM     | `1` if the kernel reports the device as removable, else `0`.    |
| TRAN   | Transport/bus, e.g. `usb`, `sata`, `nvme`, `ata`, or empty.      |
| TYPE   | `disk`, `part`, `loop`, `rom`, etc.                              |
| SIZE   | Human-readable size, e.g. `476.9G`. Not interpreted by decisions.sh, only carried through for display. |
| MODEL  | Device model string (may be empty/`-`).                          |
| SERIAL | Device serial string (may be empty/`-`).                         |

This is the same shape and column order as:

```sh
lsblk -dn -o NAME,RM,TRAN,TYPE,SIZE,MODEL,SERIAL --output-all=false
```

reformatted to tab separation (lsblk's default output is space-padded and
ambiguous once MODEL/SERIAL contain spaces; tabs keep parsing exact). The
real installer script is responsible for producing this table from `lsblk`
before calling into `decisions.sh` -- that glue code is disk I/O and is
deliberately outside this test seam.

## Function contracts

All exit codes are exposed as named constants (`DECISIONS_EXIT_OK=0`,
`DECISIONS_EXIT_FAIL=1`, `DECISIONS_EXIT_REFUSED=2`,
`DECISIONS_EXIT_AMBIGUOUS=3`) so callers and tests never hardcode numbers.

- **`filter_candidate_disks`** (stdin: full device table) -> stdout: only
  the rows that are non-removable, non-USB whole disks (`TYPE=disk`,
  `RM=0`, `TRAN` != `usb`). Always exits `0`; zero candidates is a valid
  result, not an error.

- **`resolve_target_device <typed-device>`** (stdin: full device table) ->
  on a unique match among internal disks, prints that row and exits
  `DECISIONS_EXIT_OK`. Exits `DECISIONS_EXIT_REFUSED` if the typed name is a
  real device that was filtered out (removable and/or USB). Exits
  `DECISIONS_EXIT_AMBIGUOUS` if the typed name matches zero, or more than
  one, internal disk. Accepts the typed device as either a bare name
  (`sda`) or a full path (`/dev/sda`).

- **`swap_size_from_ram_kib <ram-kib>`** -> given total RAM in KiB (the unit
  `/proc/meminfo`'s `MemTotal` line already uses), prints the hibernate
  swap size as a whole number of GiB, rounded **up**, and exits
  `DECISIONS_EXIT_OK`. Exits `DECISIONS_EXIT_FAIL` on non-positive-integer
  input.

- **`confirm_erase <resolved-device> <typed-device> <typed-word>`** ->
  exits `DECISIONS_EXIT_OK` only if `typed-device` exactly equals
  `resolved-device` and `typed-word` is exactly the literal string `ERASE`.
  Any other input (wrong path, lowercase `erase`, extra text, empty)
  exits `DECISIONS_EXIT_FAIL`.

## Running the tests

Neither `bats` nor `shellcheck` is installed system-wide; run both through
`nix shell` (the inputs are already cached, so this works offline):

```sh
nix shell nixpkgs#shellcheck --command shellcheck installer/lib/decisions.sh installer/tests/*.bats
nix shell nixpkgs#bats --command bats installer/tests/decisions.bats
```

## Building the offline installer ISO

`flake.nix`'s `nixosConfigurations.installer` output (`installer/iso.nix`) builds a
minimal NixOS installation ISO that bakes the `system` output's own toplevel closure,
plus both Intel and AMD microcode, into its own Nix store (see issue 07 and
`docs/portable-nixos-usb-installer-spec.md`, "Installer (custom self-contained offline
ISO)"). It also carries the whole git-tracked repo at `/etc/nixos-config` so the booted
environment can run `install.sh` directly.

Like the `system` output, `configuration.nix` reads `/etc/nixos/hardware-configuration.nix`
and `/etc/nixos/local.nix` by absolute path under `--impure`, so evaluating or building the
`installer` output needs a throwaway `local.nix` present at `/etc/nixos/` first (the real
`/etc/nixos/hardware-configuration.nix` on a machine that has already installed NixOS once
already exists there and is reused as a stand-in representative closure -- the point is only
to make `--impure` evaluation succeed, not to describe the eventual target hardware):

```sh
printf '{ networking.hostName = "installer-build"; }\n' | sudo tee /etc/nixos/local.nix
nix build --impure .#nixosConfigurations.installer.config.system.build.isoImage -o result-iso
sudo rm /etc/nixos/local.nix
```

This produces `result-iso/iso/nixos-offline-*.iso`. The baked target closure is large
(tens of GiB); building for real needs that much free space in `/nix` and takes a while.

Boot it with no network to confirm the installer runs fully offline (`-nic none` means QEMU
gives the guest no network device at all, so any accidental fetch attempt fails loudly
instead of silently succeeding):

```sh
nix shell nixpkgs#qemu -c qemu-img create -f qcow2 scratch.qcow2 40G
nix shell nixpkgs#qemu -c qemu-system-x86_64 -m 4G -enable-kvm \
  -cdrom result-iso/iso/nixos-offline-*.iso -nic none -drive file=scratch.qcow2,if=virtio
```

Inside the booted VM: `cd /etc/nixos-config && sudo ./installer/install.sh`.
