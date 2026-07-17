# Spec: portable generic NixOS config + offline USB installer

Status: ready-for-agent (local spec — not published to a remote tracker)
Branch: `portable-config` (isolated worktree, based on baseline `8c67057`)

## Problem Statement

I want to install my existing NixOS / Home Manager environment onto a new machine
(first target: a Dynabook X30WK) from a USB stick, **offline**, reproducibly, and
without dragging along anything machine-specific or personal — no source-host disk
UUIDs, no projects, no Yandex.Disk data, no browser profiles, no SSH/Git
credentials, and no copied login or Tailscale identity state.

Today my configuration is welded to a single AMD host: `hardware-configuration.nix`
is tracked and full of source-machine facts, graphics forces `amdgpu`, the hostname
is hardcoded, secret file paths point into `~/Yandex.Disk/...`, and the captive
portal browser is pinned to the interface `wlp1s0`. As a result the repo cannot be
cloned onto any other machine, and I also want it to become generic enough to push
to GitHub and install on arbitrary machines in the future.

## Solution

Two coordinated pieces:

1. **Make the tracked configuration generic.** One flake output, `nixosConfigurations.system`,
   that carries no machine name and no source-host hardware facts. All machine-specific
   facts are generated per install and read out-of-tree from `/etc/nixos/` under
   `--impure`. Graphics autodetect (Mesa/DRM); the captive browser discovers its Wi-Fi
   interface at runtime; secrets are read from canonical non-Yandex paths.

2. **Build a custom, self-contained, offline installer ISO.** Booted on the target, a
   strict shell installer erases a chosen internal disk, partitions it, generates the
   machine's own hardware facts, seeds the approved bootstrap secrets, installs the
   pinned generic configuration fully offline from a closure baked into the ISO, sets a
   new local password, and leaves only Tailscale authentication as a first-boot task.

The result is a fresh, reproducible install on the Dynabook — and the same artifact/flow
works for future machines — with a tracked tree that stays byte-identical to what is
pushed to GitHub.

## User Stories

1. As the person installing, I want to boot a single USB and run one installer, so that I
   don't have to perform a manual multi-step graphical NixOS install.
2. As the person installing, I want the installer to work with no network, so that I can
   install in places without usable connectivity (e.g. behind a captive portal).
3. As the person installing, I want to explicitly choose the target disk from a listed set
   of internal disks, so that I never rely on the installer guessing.
4. As the person installing, I want the installer to refuse removable/USB devices as
   targets, so that I can never accidentally erase the installer stick itself.
5. As the person installing, I want the installer to print the target's model, serial, and
   size before doing anything, so that I can confirm I'm erasing the right drive.
6. As the person installing, I want to type a two-part confirmation (the exact device path
   plus the word `ERASE`), so that a single keystroke can't trigger a destructive wipe.
7. As the person installing, I want the installer to abort on any ambiguity rather than
   proceed, so that unclear situations fail safe.
8. As the person installing, I want the installer to size a swap partition to the machine's
   RAM automatically, so that hibernate works without me computing a number.
9. As the person installing, I want to set a new login password during install, so that the
   machine is immediately usable and secure with no known-password window.
10. As the person installing, I want the installer to generate the machine's own hardware
    configuration after partitioning, so that disk UUIDs, kernel modules, and CPU microcode
    match the actual hardware.
11. As the person installing, I want approved bootstrap secrets copied to their expected
    persistent locations, so that declared services (proxy, dictation) work immediately.
12. As the person installing, I want the USB copies of those secrets retained as recovery
    material, so that I can re-seed later if needed.
13. As the daily user, I want the Dynabook's hostname to be `dynabook-x30wk`, so that it is
    identifiable on my network and in Tailscale.
14. As the daily user, I want hibernate to work exactly as it does on my current machine, so
    that suspend-to-disk behaves the same.
15. As the daily user, I want graphics to just work on the Dynabook's Intel GPU without me
    configuring drivers, so that the Wayland/Hyprland session comes up correctly.
16. As the daily user, I want the captive portal browser to find whatever Wi-Fi interface is
    actually active, so that captive portals work regardless of the interface name.
17. As the daily user, I want the captive browser to never bind a Tailscale or virtual
    interface, so that portal auth targets the real physical network device.
18. As the daily user, I want my full current feature set on the Dynabook (including the
    proxy and dictation tooling), so that the environment is a faithful reproduction.
19. As the daily user, I want to authenticate Tailscale as a new node on first boot, so that
    the Dynabook joins my tailnet with its own identity.
20. As a security-conscious user, I want no password hashes or login state copied from the
    source machine, so that credentials are never transplanted.
21. As a security-conscious user, I want no Tailscale identity/state copied, so that the new
    node has independent, revocable credentials.
22. As a security-conscious user, I accept that the USB carries the needed bootstrap secrets
    in plaintext, but I want their contents never recorded in the repo, commits, docs, or
    logs, so that the risk stays confined to the physical stick.
23. As the config maintainer, I want a single generic flake output rebuilt the same way on
    every machine (`--flake .#system`), so that I don't maintain a per-host output list.
24. As the config maintainer, I want the tracked tree to stay byte-identical to GitHub with
    no staged machine junk, so that clone/push stays clean.
25. As the config maintainer, I want machine facts to live at a well-known path outside the
    repo, so that the repo has no per-machine divergence.
26. As the config maintainer, I want to edit my config as my normal user without sudo, so
    that day-to-day tweaks stay low-friction.
27. As the config maintainer, I want the installed clone to have my GitHub remote preset, so
    that later updates are a manual `git pull` + rebuild.
28. As the config maintainer, I want updates to be manual (no auto-update, no re-flashing for
    routine changes), so that I stay in control of when the system changes.
29. As the config maintainer, I want the source machine's AMD-only early-KMS initrd hack out
    of the generic config, so that it doesn't wrongly apply to other machines.
30. As the config maintainer, I want to trust that the captive-browser module on the pinned
    nixpkgs is not affected by CVE-2026-25740 before shipping it, so that I don't reintroduce
    a known privilege escalation.
31. As the installer author, I want the installer's decision logic unit-tested, so that
    target-selection safety and sizing math don't silently regress.
32. As the installer author, I want tests to exercise external behavior (inputs → decision),
    not internal implementation, so that the tests stay meaningful under refactor.

## Implementation Decisions

### Configuration generalization

- Collapse to a single generic flake output named `system`
  (`nixosConfigurations.system`); rebuild everywhere with `--flake .#system --impure`.
  The username stays `andongni`; only the machine-name/output coupling is removed.
- Adopt an **out-of-tree machine-facts contract** (model ii): the configuration reads
  generated facts from `/etc/nixos/` via absolute paths under `--impure`. Two generated
  files: the standard generated hardware configuration, and a small local file setting
  `networking.hostName`. The tracked tree carries no machine name and no source-host
  hardware facts.
- The previously tracked hardware configuration is removed from version control and
  gitignored; the top-level configuration imports the `/etc/nixos` facts instead of a
  tracked in-tree file.
- Graphics policy becomes generic: keep accelerated-graphics enablement (and 32-bit
  support if already used); remove the forced X-server `amdgpu` video driver (inert under
  Wayland/Hyprland and wrong on Intel); the AMD early-KMS initrd module is dropped from the
  generic config (already committed on this branch).
- Hibernate stays a generated-facts concern: the installer creates a dedicated swap
  partition, hardware generation records its UUID, and NixOS auto-derives resume. No
  machine-specific resume config enters the tracked tree. The existing hibernate launcher
  entry stays as generic UI.
- **Secrets** move to canonical, non-Yandex locations split by trust boundary:
  - The proxy (root) config file is read by absolute path from a root-owned system secrets
    directory under `/etc/nixos/secrets/`.
  - The dictation (user) credential source is read from a user-owned config directory and
    copied to its existing runtime path at home-manager activation as today.
  - Both modules stop hardcoding the Yandex.Disk repo path.
- **Captive-browser interface discovery (Shape B):** drop the static interface option. The
  NetworkManager dispatcher validates the interface it is handed (must be a physical
  NetworkManager device of type wifi/ethernet; reject tailscale/virtual/loopback) and
  launches a parameterized captive-browser instance bound to that interface. Requires
  confirming the tool's real runtime interface-override support before implementation.

### Repository / machine layout on an installed system

- The config clone lives at `~/.nixos-config` (user-owned, outside Yandex.Disk).
- `/etc/nixos/` holds only generated facts and the root-owned system secret(s).
- The clone's `origin` is preset to the GitHub remote; updates are manual `git pull` +
  rebuild. The generic work is intended to merge into `master`, which installed machines
  track.

### Installer (custom self-contained offline ISO)

- The ISO is built from the finished `portable-config` tip and bakes a **representative**
  system closure (covering both Intel and AMD microcode, and the generically-enabled
  redistributable firmware) into its own Nix store, so `nixos-install` builds only the cheap
  top-level derivation and fetches nothing. This is an honest representative closure, not a
  claimed exact target closure.
- Install sequence: interactive target selection and confirmation → partition (GPT: EFI
  System Partition + swap sized to detected RAM + one unencrypted ext4 root that also holds
  `/home`; no LUKS, no separate `/home`) → generate the machine's hardware facts against the
  mounted target → write the local file with `networking.hostName = "dynabook-x30wk"` → seed
  approved secrets to their persistent paths (retaining USB copies) → `nixos-install` the
  generic config offline → prompt for and set a new login password inside the target
  (`mutableUsers` stays true; passwordless sudo unchanged) → populate `~/.nixos-config` from
  the baked repo and set the GitHub `origin`.
- **Target-selection contract:** enumerate only non-removable, non-USB-bus disks; print
  each candidate's model/serial/size; require the operator to type the exact target device;
  refuse removable/USB devices outright; abort if input does not uniquely match a listed
  internal disk. **Confirmation gate:** re-print resolved model/serial/size, then require a
  two-part typed confirmation (retype the full device path *and* type `ERASE`); no default,
  no timeout-to-yes.
- First boot leaves exactly one interactive task: `tailscale up` to join the tailnet as a
  new node. No Tailscale identity or state is copied.

## Testing Decisions

- **What is tested:** only the **installer** script. The configuration files (Nix modules /
  the portable refactor) get **no new test seam** — they remain verified by the existing gate
  (pre-commit hooks and `nixos-rebuild` evaluation), consistent with current repo practice.
- **Seam:** installer shell-logic unit tests at the highest single seam available for the
  script — its pure decision functions, exercised as inputs → decision/exit with mocked
  inputs (no real disks). Coverage:
  - target enumeration filtering (non-removable, non-USB only),
  - refusal of removable/USB targets,
  - abort-on-ambiguity when input doesn't uniquely match,
  - swap-size-from-RAM computation,
  - two-part confirmation parsing (exact device path + `ERASE`, reject anything else).
- **Good test = external behavior only.** Tests assert the decision/exit an input produces,
  not internal variables or command wording, so they survive refactors of the script's
  internals.
- **Structure to enable it:** the installer is organized so its decision logic is callable
  in isolation (sourceable functions guarded from executing the destructive path), so tests
  run without touching hardware.
- **Prior art:** none in this repo for shell tests; introduce a lightweight shell test
  harness (e.g. bats) plus shellcheck. This is the first installer test seam.

## Out of Scope

- Copying any user data: projects, Yandex.Disk contents, browser profiles, caches, SSH
  identities, Git credentials, or accumulated home-directory state.
- Copying login state / password hashes, or Tailscale identity / mutable state.
- Disk encryption (LUKS), dual-boot, a separate `/home`, or data migration.
- Per-host tracked flake outputs; the design is a single generic output plus generated
  ignored local facts.
- The source (AMD) machine's early-KMS initrd HDMI workaround in the generic config; whether
  it is still needed on that live host is a separate experiment on that machine, not part of
  this work.
- Automated tests for the configuration/Nix modules (no new config test seam).
- Pushing the config to GitHub and merging `portable-config` into `master` (a later step).
- Running the install against real Dynabook hardware (this spec covers building and locally
  testing the installer, not the physical rollout).
- Any change to the active main checkout or the other agent's worktree.

## Further Notes

**To verify before/within implementation (facts, not decisions):**
- Exact Nix behavior for importing `/etc/nixos/*.nix` absolute paths under `--impure` during
  `nixos-install` (installer-environment `/etc/nixos` vs target `/mnt/etc/nixos`).
- How the ISO embeds the chosen representative closure and that `nixos-install` sources
  purely from the local store offline.
- captive-browser's real runtime interface-override support (config/env/CLI), since the
  module bakes the interface statically today.
- Whether the locked `nixpkgs` revision includes the captive-browser fix for
  **CVE-2026-25740**; if not, a separate decision (bump nixpkgs / overlay-patch / keep the
  module disabled) is required.

**Guardrails:**
- All work stays on the isolated `.worktrees/portable-config` branch; never touch the main
  checkout or the other agent's worktree.
- No rebuild against the live source host. Per repo policy, scoped commits are the unit of
  work and pre-commit hooks are the verification gate.

**Baseline:** branch based on `8c67057` (intentionally excludes the later Hyprwhispr commits
currently on `master`); the initrd-`amdgpu` removal is already committed as `e1bbe61`.
