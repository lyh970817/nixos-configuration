# ONLYOFFICE Desktop Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install ONLYOFFICE Desktop Editors alongside LibreOffice through the existing Home Manager desktop package list.

**Architecture:** Keep the change in the current application-management layer by modifying the existing Home Manager desktop package module. Verify the result by rebuilding the NixOS flake with the required host target and checking that ONLYOFFICE is exposed as a desktop application in the resulting environment.

**Tech Stack:** NixOS flakes, Home Manager, `pkgs.onlyoffice-desktopeditors`

---

### Task 1: Add ONLYOFFICE to the desktop package set

**Files:**
- Modify: `home/packages/desktop.nix`
- Verify: `home/packages/desktop.nix`

- [ ] **Step 1: Update the desktop package list**

Add `onlyoffice-desktopeditors` to the existing `home.packages = with pkgs; [ ... ]` list in `home/packages/desktop.nix`, keeping `libreoffice-fresh` installed.

- [ ] **Step 2: Review the package diff**

Run: `git diff -- home/packages/desktop.nix`

Expected: the diff shows only the addition of `onlyoffice-desktopeditors` in the existing desktop application list.

### Task 2: Apply and verify the system change

**Files:**
- Verify: `home/packages/desktop.nix`
- Verify: Home Manager application entries in the activated system

- [ ] **Step 1: Rebuild the system**

Run: `sudo nixos-rebuild switch --flake .#andongni --impure`

Expected: rebuild exits successfully and activates the updated Home Manager profile.

- [ ] **Step 2: Verify ONLYOFFICE is exposed as a desktop app**

Run: `find ~/.nix-profile/share/applications ~/.local/share/applications -maxdepth 2 -type f 2>/dev/null | rg 'onlyoffice|desktopeditors'`

Expected: at least one ONLYOFFICE desktop entry is present in the user profile.

- [ ] **Step 3: Review the resulting diff**

Run: `git diff -- home/packages/desktop.nix docs/superpowers/plans/2026-03-24-onlyoffice-desktop-installation.md`

Expected: the working tree shows only the planned package-list change and the plan document in this scope.
