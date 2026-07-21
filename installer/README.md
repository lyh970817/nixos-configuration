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
  deliberately stay free of. It also prompts interactively for the machine's
  `portable.role` (`home` or `remote`), `networking.hostName`, and
  `portable.peerHost` -- validated with `validate_role`/`validate_hostname`,
  with `default_hostname` offering `dynabook-x30wk` as the default hostname
  for `remote` installs (no default for `home`) and `default_peer_host`
  offering a default peer for `remote` installs --
  and writes all three into the generated `local.nix` alongside
  `portable.configDir`. Not part of the automated test seam above; it
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

- **`validate_role <value>`** -> exits `DECISIONS_EXIT_OK` if `value` is
  exactly `home` or `remote` (the two `portable.role` enum members),
  `DECISIONS_EXIT_FAIL` otherwise.

- **`validate_hostname <value>`** -> exits `DECISIONS_EXIT_OK` if `value` is
  a valid RFC1123-ish single-label hostname (lowercase letters, digits, and
  hyphens only; 1-63 characters; must not start or end with a hyphen),
  `DECISIONS_EXIT_FAIL` otherwise.

- **`default_hostname <role>`** -> prints the sensible default
  `networking.hostName` for `role` and always exits `DECISIONS_EXIT_OK`.
  Prints `dynabook-x30wk` for role `remote` (this physical laptop's
  hostname is known in advance); prints nothing for role `home` (the home
  machine's hostname varies and the operator must type one).

- **`default_peer_host <role>`** -> prints the sensible default
  `portable.peerHost` for `role` and always exits `DECISIONS_EXIT_OK`.
  Prints `home` for role `remote` (the remote machine's peer is always the
  home machine's stable MagicDNS alias); prints nothing for role `home`
  (the home machine's peer is the remote's chosen hostname, which this
  function has no way to know -- the installer prompts for it separately).

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
ISO)"). It carries the flake source tree at `/etc/nixos-config` so the booted environment
can run `install.sh` directly. Because Nix strips `.git` from that source, the ISO also
carries `/etc/nixos-config.bundle`, generated at the clean flake revision used by the ISO
build. The installer clones that bundle fully offline, then changes `origin` to
`git@github.com:lyh970817/nixos-configuration.git`; the checked-out `master` branch therefore
has real history, a tracked index, and a normal `origin/master` upstream without putting SSH
keys or other Git authentication material on the ISO.

The ISO must be built from the clean `master` tip of the canonical checkout at
`/home/andongni/.nixos-config`. During impure evaluation, `iso.nix` resolves that checkout's
real `refs/heads/master` from either its loose ref or `packed-refs`, then requires it to equal
the exact flake commit in `self.rev`. Dirty, non-Git, detached, and non-`master` flake sources
fail evaluation instead of manufacturing a `master` branch from an arbitrary revision. A
revision missing from the imported object database fails the bundle build.

The ISO may also carry an optional coding-CLI convenience payload from the build
machine's `/home/andongni/.nixos-config/secrets/coding-cli` directory. When that
directory exists, it is exposed in the booted installer as
`/etc/nixos-secrets/coding-cli`; when it does not exist, the ISO omits the path
and still evaluates normally. This payload is limited to credentials; profiles
and agent configuration are tracked in the repository and are deployed by Home
Manager after installation. Its supported layout is:

```
secrets/coding-cli/
  claude/default/.credentials.json
  claude/mattpocock/.credentials.json
  codex/auth.json
  codex/auth_1.json
```

Only supported credentials are copied into the ISO; the installer ignores other
files in the ignored source directory.

For compatibility with existing installer media, the deprecated flat path
`claude/.credentials.json` is also accepted for the `default` profile. When
both it and `claude/default/.credentials.json` exist, the new per-profile path
takes precedence. The ISO normalizes either accepted default credential to
`claude/default/.credentials.json` in its filtered payload. Move to the
per-profile path before relying on any future payload layout changes.

`install.sh` copies each available credential to its corresponding target with
private permissions: `default` goes to
`~/.config/claude/.credentials.json`, `mattpocock` goes to
`~/.config/claude-mattpocock/.credentials.json`, and Codex auth files go to
`~/.codex/`. It reports each Claude profile separately. Every entry is optional:
if the payload directory or an individual credential is absent, installation
continues and that profile simply needs a later login. The installer never copies
Codex `*.config.toml` files from `secrets/`; a fresh installation receives the
tracked profile definitions when Home Manager activates.

The payload is copied into the ISO's Nix store in cleartext. Treat every ISO
that includes it as credential-bearing media: keep it private, erase or destroy
it when it is no longer needed, and build without this directory when portable
login seeding is not appropriate.

The derivation imports only `.git/objects`, then constructs a new builder-owned bare repository
whose sole ref is the already-verified `master`. Repository config, credential files, hooks,
refs (including the stash ref), reflogs, the index, and worktree metadata are not imported. The
complete object database is an intermediate Nix store input, however, so it can include
unreachable or dangling objects—including objects formerly reachable through a stash—and
remains locally visible in that store path until garbage-collected. The final ISO
bundle includes only history reachable from `master`; that history necessarily includes any
secrets committed historically to the branch. Commit the intended installer/config state and
build from canonical `master` so the bundle and flake source describe the same revision.

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
