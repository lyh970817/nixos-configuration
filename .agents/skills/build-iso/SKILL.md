---
name: build-iso
description: Build (and, when explicitly confirmed, burn) the self-contained offline NixOS installer ISO from this repository's `nixosConfigurations.installer` flake output. Use whenever the user asks to build, rebuild, or write the installer ISO to a USB disk.
---

# Build the Offline Installer ISO

Full background: `docs/portable-nixos-usb-installer-spec.md` and `installer/README.md`
("Building the offline installer ISO"). This skill is the operational checklist.

## 1. Preconditions

1. The build must run from the canonical checkout at `/home/andongni/.nixos-config` on a
   clean `master` tip. `installer/iso.nix` hardcodes that path and reads its real
   `refs/heads/master` directly; it throws if the flake source is dirty, detached, or not
   exactly that revision. Never build from a `.claude/worktrees/*` checkout — its branch
   isn't `master` and can't satisfy this check.
2. Get a clean tree without touching `.claude/worktrees/*`: those are other sessions'
   isolated checkouts (own nested `.git`), never stash, commit, or delete them. Commit or
   `git stash push -u -- <paths>` only the unrelated files that are actually yours.
3. `/etc/nixos/local.nix` must exist (any content) for `--impure` evaluation to succeed;
   on an already-installed host it's already there. If missing, a throwaway
   `{ networking.hostName = "installer-build"; }` is enough — remove it after the build.
4. Free space: the baked closure is tens of GiB. Check `df -h /` first; if it's tight, run
   `nix-collect-garbage -d` (and `sudo nix-collect-garbage -d` for system generations)
   before building rather than risking a build that fails from ENOSPC partway through.

## 2. Build

```sh
nix build --impure .#nixosConfigurations.installer.config.system.build.isoImage -o result-iso
```

This is slow (large closure to bake and squash) — run it in the background and keep
checking `df -h /` isn't heading to zero. Output: `result-iso/iso/nixos-offline-*.iso`.

## 3. Optional offline boot check

```sh
nix shell nixpkgs#qemu -c qemu-img create -f qcow2 scratch.qcow2 40G
nix shell nixpkgs#qemu -c qemu-system-x86_64 -m 4G -enable-kvm \
  -cdrom result-iso/iso/nixos-offline-*.iso -nic none -drive file=scratch.qcow2,if=virtio
```

`-nic none` gives the guest no network device, so any accidental fetch fails loudly instead
of silently succeeding. Inside the VM: `cd /etc/nixos-config && sudo ./installer/install.sh`.

## 4. Burning to a USB disk — confirm before writing

Writing the ISO to a disk with `dd` is irreversible and erases the entire destination
device, not just the partition install target would pick. Never guess the device:

1. `lsblk -o NAME,SIZE,TYPE,TRAN,MODEL,FSTYPE,LABEL,MOUNTPOINT` and `sudo blkid` to
   identify the exact `/dev/sdX` (whole disk, not a partition), its size/model, and
   whatever filesystem/label is already on it.
2. Confirm nothing on that disk is mounted (`findmnt /dev/sdX*`).
3. State the resolved device, its current label/contents, and get explicit user
   confirmation before writing — an existing label (e.g. a Windows installer disk) means
   real data would be destroyed. Do not proceed on an assumption that "the only USB disk
   plugged in" is the intended target.
4. Only after confirmation:
   ```sh
   sudo dd if=result-iso/iso/nixos-offline-*.iso of=/dev/sdX bs=4M status=progress oflag=direct
   sync
   ```

## 5. Payload and secrets caveat

The ISO can bake an optional `secrets/coding-cli` credentials payload and an SSH key for
first-boot `git push` (see `installer/README.md` for the exact layout and target paths).
Both land in the ISO's Nix store in cleartext — treat any ISO built with them present as
credential-bearing media: keep it private and destroy it when no longer needed.
