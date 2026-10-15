---
name: peer-device-access
description: Reach the user's other machine — its files, screen, and shell — from any project. Use whenever the user mentions "my laptop", "on the laptop", the portable, `dynabook-x30wk`, a screenshot or file on the laptop, or "the other machine" while this session runs on the desktop; and the reverse ("my desktop", "home machine", `linglong`) while it runs on the laptop. For configuration changes or rebuilds on the peer, use `work-on-peer-device` in ~/.nixos-config instead.
---

# Peer device access

The user has two NixOS machines: the desktop `linglong` (role `home`) and the
laptop `dynabook-x30wk` (role `remote`). A request about "my laptop" from a
desktop session concerns the peer, not this host.

1. **Identify the local host first.** Run `hostname` and read
   `/etc/nixos/local.nix` for `portable.role` and `portable.peerHost`
   (`dynabook-x30wk` on the desktop, `home` on the laptop). If the user's
   phrase names the peer, never search this host's files for it, even when
   they give a path such as `Pictures/Screenshots`; that path is on the peer.
2. **Files:** the peer's home is a lazy SSHFS automount at `~/<peerHost>`
   (`~/dynabook-x30wk` on the desktop, `~/home` on the laptop). Read and copy
   through it directly; list newest first with `ls -t`.
3. **Commands:** `ssh <peerHost> '...'` over Tailscale SSH, with the whole
   remote command quoted as one string (unquoted `&&` runs locally). For
   anything multi-line, `ssh <peerHost> bash -s < script`. SSH lands in `$HOME`.
4. **Screenshots:** saved as `screenshot_YYYY-MM-DD_HH-MM-SS.png` in
   `~/Pictures/Screenshots`. For "my most recent screenshot on my laptop":
   `ls -t ~/dynabook-x30wk/Pictures/Screenshots | head -1`, then open it with
   the Read tool through the mount.
5. **Live capture:** SSH sessions carry no Wayland environment, so set it:
   ```sh
   ssh <peerHost> 'f=$(mktemp ~/peer-capture-XXXXXX.png) && XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 grim "$f" && echo "$f"'
   ```
   Read the printed file through `~/<peerHost>/`, then delete exactly that
   file with `ssh <peerHost> 'rm -f <path>'`. Use `grim -g "x,y wxh"` for a
   region.
6. **Peer unreachable:** if the mount or SSH fails, report the actual error
   (command and message). Do not fall back to searching locally as if this
   host were the peer, and do not ask the user to copy the file until you have
   tried both the mount and SSH.

Scope: this skill covers reading the peer's files, screen and shell. For any
configuration change, Git transfer, or rebuild on the peer, follow the
repo-local `work-on-peer-device` skill in `~/.nixos-config`.
