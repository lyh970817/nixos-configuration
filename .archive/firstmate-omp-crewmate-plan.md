# First Mate OMP Crewmate Integration Plan

## Goal

Make OMP a verified First Mate crewmate harness while preserving the intended hierarchy:

```text
First Mate primary (OMP; native OMP delegation disabled)
  └── OMP crewmate (First Mate-managed task and worktree)
        └── OMP-native nested agents (crewmate-internal)
```

First Mate owns only the top-level crewmate lifecycle: task metadata, Treehouse worktree, tmux/Herdr endpoint, watcher supervision, status events, and teardown. Nested OMP agents remain internal to the parent crewmate and do not receive First Mate task IDs, fleet metadata, or separate status files.

## Decisions and boundaries

- Keep nested OMP filesystem isolation delegated to OMP; default `task.isolation.mode = none` is acceptable for the initial design.
- Keep OMP batching available, but treat concurrent editing in one crewmate worktree as the parent model's responsibility.
- Disable native OMP delegation only for the First Mate primary. Delegation remains available in an OMP crewmate's linked worktree.
- Do not change Treehouse allocation, Herdr workspace ownership, First Mate status vocabulary, or nested-agent lifecycle tracking.
- Do not register nested OMP agents as First Mate fleet items.
- Prefer reuse of the existing Pi-compatible First Mate extensions and supervision paths; add OMP-specific behavior only where live verification proves it is necessary.

## Phase 1: Probe OMP compatibility

1. Verify the OMP launch contract needed by First Mate: `--model`, thinking/effort mapping, `-e` extension loading, launch-brief delivery, and project/worktree startup.
2. Verify that the existing Pi-compatible per-task turn-end extension works in an OMP crewmate.
3. Identify OMP's native task tool event/configuration surface and verify a primary-only way to disable native delegation without disabling it in crewmates.
4. Capture OMP's busy footer, composer, idle prompt, trust behavior, and clean-exit behavior under tmux and Herdr.
5. Confirm the effective nested-task settings and whether the tracked OMP task settings are applied to the intended primary and crewmate profiles.

## Phase 2: Add the verified harness adapter

1. Add `omp` as an explicit verified crewmate harness in `bin/fm-harness.sh` and `bin/fm-spawn.sh` without changing the current primary marker that treats the `firstmate` wrapper as Pi-compatible.
2. Add an OMP launch template that passes the encoded First Mate launch brief, model, thinking/effort settings, and the verified turn-end extension.
3. Record `harness=omp` in task metadata and preserve normal respawn/recovery resolution.
4. Add only the OMP-specific environment markers or profile selection required to distinguish primary OMP sessions from crewmate OMP sessions.
5. Keep `config/crew-harness` as the local opt-in selector; do not make OMP the default until the adapter passes verification.

## Phase 3: Preserve primary-only delegation

1. Add a First Mate primary OMP profile/config overlay that removes or disables OMP-native task delegation.
2. Ensure the restriction is scoped to the genuine primary home, not linked crewmate worktrees.
3. If OMP configuration cannot remove the delegation surface, add an OMP-compatible primary tool-call guard that reuses the existing First Mate primary-scope predicate and allows linked crewmate worktrees.
4. Keep ordinary OMP sessions outside First Mate unaffected.

## Phase 4: Integrate supervision

1. Reuse the Pi turn-end extension if its OMP behavior is verified; otherwise add the smallest OMP-specific turn-end adapter.
2. Register an OMP busy signature in `bin/fm-tmux-lib.sh` or reuse the Pi signature only after verification.
3. Extend composer/idle classification only if OMP's rendered composer differs from Pi's.
4. Confirm the existing Herdr native agent-state path remains valid for `harness=omp`; add an OMP-specific Herdr registration detail only if required.
5. Verify that the watcher observes only the parent crewmate and that parent status events remain the sole First Mate return channel.

## Phase 5: Verification and documentation

1. Add deterministic unit coverage for harness resolution, launch flags, metadata, model/effort handling, and primary/crewmate delegation scope.
2. Add a tmux smoke path that spawns an OMP crewmate, delivers the brief, exercises a nested OMP task, observes the parent turn-end signal, and tears down safely.
3. Add the corresponding Herdr smoke path when the installed Herdr runtime is available.
4. Verify shared-worktree nested behavior with read-only children and with a deliberately serialized edit; do not require nested worktree isolation.
5. Verify that the primary cannot invoke native OMP delegation while an OMP crewmate can.
6. Update `AGENTS.md`, `docs/subagent-guard.md`, `docs/configuration.md`, the harness-adapters skill, and runtime verification documentation with the final adapter contract.
7. Record the effective OMP profile settings used by the primary and crewmates, including recursion depth, batching, and isolation mode.

## Acceptance criteria

- `config/crew-harness` can select `omp` and `fm-spawn.sh` launches a supervised OMP crewmate.
- The OMP crewmate receives the normal First Mate brief and writes normal parent status events.
- The First Mate watcher and turn-end supervision remain correct under tmux and Herdr.
- Native OMP delegation is unavailable in the First Mate primary but available inside the linked crewmate worktree.
- Nested OMP agents can use the crewmate's shared worktree without First Mate creating duplicate fleet records.
- Existing Pi, Claude, Codex, and ordinary OMP workflows remain unchanged.
- Unsupported or unverified OMP behavior fails loudly rather than silently falling back to an unmanaged launch.

## Expected change size

The likely implementation is approximately 200-500 added lines including adapter code, primary gating, tests, and documentation. The lower end applies if OMP reuses the existing Pi extension and busy/composer signatures; OMP-specific tool-call or TUI behavior would increase the total.

## Outcome — 2026-08-02

- OMP and Claude parents were both spawned under Herdr in isolated Treehouse copies.
- OMP native nested delegation returned `OMP nested delegation works`.
- Claude native nested delegation returned `Claude nested delegation works`.
- Herdr navigation is configured: `Alt+E`, `Alt+Up`, and `Alt+Down`.
- Pi Calm is Pi-only and unsupported by OMP.
- The live failure was not a Nix configuration problem; it was caused by two Firstmate Herdr startup races: input before first render and premature OMP no-agent classification.
- A tested candidate fix exists only in `/home/andongni/.cache/firstmate-herdr-fix` on `fix/herdr-initial-input-race`; it is not active in `/home/andongni/firstmate` and should be upstreamed to Firstmate rather than duplicated in Nix configuration.
