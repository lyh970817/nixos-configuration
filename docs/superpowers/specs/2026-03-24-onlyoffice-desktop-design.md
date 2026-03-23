# ONLYOFFICE Desktop Installation Design

## Goal

Install ONLYOFFICE Desktop Editors on this machine without removing LibreOffice.

## Current Context

- This repository manages GUI desktop applications through Home Manager.
- User-facing desktop packages are declared in [home/packages/desktop.nix](/home/andongni/Yandex.Disk/System/nixos-configuration/home/packages/desktop.nix).
- LibreOffice is already installed there as `libreoffice-fresh`.

## Chosen Approach

Add `pkgs.onlyoffice-desktopeditors` to the existing `home.packages` list in `home/packages/desktop.nix`.

## Alternatives Considered

1. Add ONLYOFFICE alongside LibreOffice in `home/packages/desktop.nix`.
   Recommended because it matches the current repository structure and is the smallest change.
2. Split office software into a separate Home Manager package module.
   Rejected because it adds structure without solving a current problem.
3. Install ONLYOFFICE at the NixOS system layer.
   Rejected because this repository currently places desktop GUI applications in Home Manager.

## Implementation Notes

- Keep `libreoffice-fresh` installed.
- Add `onlyoffice-desktopeditors` next to the existing office applications.
- Apply the change using:

```sh
sudo nixos-rebuild switch --flake .#andongni --impure
```

## Testing

- Confirm the flake evaluates during rebuild.
- Confirm the rebuild completes successfully.
- Confirm an ONLYOFFICE Desktop Editors launcher entry or `.desktop` file is present in the resulting user environment.

## Scope

This change only installs the desktop editor package. It does not configure file associations, remove LibreOffice, or add ONLYOFFICE server components.
