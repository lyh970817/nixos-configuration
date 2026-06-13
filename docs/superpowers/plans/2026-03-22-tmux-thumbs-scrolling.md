# Tmux Thumbs And Copy-Mode Scrolling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `flash.nvim`-style labeled visible-text jumping to tmux and restrict `C-b`/`C-f` paging to `copy-mode-vi`.

**Architecture:** Keep tmux declarative in Home Manager by extending the existing tmux module. Use Home Manager's native tmux plugin support for `tmux-thumbs`, and implement paging through tmux copy-mode table bindings rather than another scrolling plugin.

**Tech Stack:** NixOS flakes, Home Manager, tmux, `pkgs.tmuxPlugins.tmux-thumbs`

---

### Task 1: Update tmux configuration

**Files:**
- Modify: `home/programs/tmux.nix`
- Verify: generated Home Manager tmux config after rebuild

- [ ] **Step 1: Add the tmux plugin declaration**

Use `programs.tmux.plugins` with `pkgs.tmuxPlugins.tmux-thumbs`, and set plugin options in `extraConfig` so the binding does not conflict with existing tmux keys.

- [ ] **Step 2: Add copy-mode-only paging bindings**

Bind `C-b` and `C-f` in the `copy-mode-vi` table to `page-up` and `page-down`, without creating normal-mode bindings.

- [ ] **Step 3: Keep the existing copy workflow intact**

Retain `M-v` for entering copy mode and preserve the clipboard copy bindings already present.

### Task 2: Apply and verify the system change

**Files:**
- Verify: `home/programs/tmux.nix`
- Verify: generated tmux config under Home Manager output

- [ ] **Step 1: Rebuild the system**

Run: `sudo nixos-rebuild switch --flake .#andongni --impure`

Expected: rebuild exits successfully and activates the updated Home Manager tmux configuration.

- [ ] **Step 2: Inspect generated tmux config**

Confirm the generated config contains the `tmux-thumbs` plugin block and the `copy-mode-vi` bindings for `C-b` and `C-f`.

- [ ] **Step 3: Review the diff**

Run `git diff -- home/programs/tmux.nix docs/superpowers/plans/2026-03-22-tmux-thumbs-scrolling.md` and confirm the change is limited to the planned tmux update and plan doc.
