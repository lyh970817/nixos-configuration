# Quick Reference Guide

## Common Operations

### Building and Switching

```bash
# Switch to new configuration
cd /home/andongni/Yandex.Disk/System/nixos-configuration
sudo nixos-rebuild switch --flake .#andongni

# Test configuration without activating
sudo nixos-rebuild test --flake .#andongni

# Build without activating
sudo nixos-rebuild build --flake .#andongni

# Dry build (check for errors)
sudo nixos-rebuild dry-build --flake .#andongni
```

### Updating

```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
nix flake lock --update-input home-manager

# Apply updates
sudo nixos-rebuild switch --flake .#andongni
```

### Managing Modules

#### Enable a Module
Uncomment or add the import in `configuration.nix`:
```nix
imports = [
  ./modules/services/new-service.nix
];
```

#### Disable a Module
Comment out the import:
```nix
imports = [
  # ./modules/services/unwanted-service.nix
];
```

### Adding New Packages

#### System Packages
Add to appropriate module in `modules/programs/`:
```nix
environment.systemPackages = with pkgs; [
  new-package
];
```

#### User Packages
Add to appropriate file in `home/packages/`:
```nix
home.packages = with pkgs; [
  new-package
];
```

### Git Operations

```bash
# Check status
git status

# Add changes
git add .

# Commit changes
git commit -m "Description of changes"

# View history
git log --oneline
```

### Rollback

```bash
# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Rollback to previous generation
sudo nixos-rebuild switch --rollback

# Switch to specific generation
sudo nix-env --switch-generation <number> --profile /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

### Cleaning Up

```bash
# Remove old generations (older than 30 days)
sudo nix-collect-garbage --delete-older-than 30d

# Remove all old generations
sudo nix-collect-garbage -d

# Optimize nix store
nix-store --optimize
```

### Checking Configuration

```bash
# Check flake syntax
nix flake check

# Show flake info
nix flake show

# Show flake metadata
nix flake metadata
```

### Home Manager Operations

```bash
# Home Manager is integrated into nixos-rebuild
# Changes to home/ directory are applied with:
sudo nixos-rebuild switch --flake .#andongni

# Check Home Manager configuration
home-manager --version
```

## Module Organization

### System Modules (`modules/`)
- **system/**: Core system settings (boot, networking, locale)
- **desktop/**: Desktop environment (Hyprland, XDG portals)
- **hardware/**: Hardware support (audio, bluetooth, printing)
- **services/**: System services (greetd, yandex-disk, mihomo, keyd)
- **programs/**: System-level programs (input method, firefox, dev tools)

### Home Manager (`home/`)
- **programs/**: User program configurations (shell)
- **desktop/**: Desktop theming and appearance
- **packages/**: User package lists (base, desktop, development, fonts)

### Users (`users/`)
- User account definitions

## File Locations

- **Main config**: `/home/andongni/Yandex.Disk/System/nixos-configuration/configuration.nix`
- **Flake**: `/home/andongni/Yandex.Disk/System/nixos-configuration/flake.nix`
- **Backup**: `/home/andongni/Yandex.Disk/System/nixos-configuration/configuration.nix.backup`
- **Hardware**: `/home/andongni/Yandex.Disk/System/nixos-configuration/hardware-configuration.nix`

## Useful Commands

```bash
# Search for packages
nix search nixpkgs <package-name>

# Show package info
nix-env -qa --description <package-name>

# Check which packages are installed
nix-env -q

# Show system configuration
nixos-option system.stateVersion

# Show Home Manager configuration
home-manager --help
```

## Troubleshooting

### Configuration Errors
```bash
# Check syntax
nix flake check

# Dry build
sudo nixos-rebuild dry-build --flake .#andongni

# Show detailed trace
sudo nixos-rebuild switch --flake .#andongni --show-trace
```

### Service Issues
```bash
# Check service status
systemctl status <service-name>

# View service logs
journalctl -u <service-name>

# Restart service
sudo systemctl restart <service-name>
```

### Git Issues
```bash
# Flakes require clean git tree
git add .
git commit -m "WIP"

# Or use --impure flag (not recommended)
sudo nixos-rebuild switch --flake .#andongni --impure
```

## Theme Switching

```bash
# Switch to dark mode
switch-dark

# Switch to light mode
switch-light
```

## Important Paths

- System configuration: `/etc/nixos/` (symlinked to your flake)
- Nix store: `/nix/store/`
- User profiles: `~/.nix-profile/`
- System profiles: `/nix/var/nix/profiles/system/`
- Home Manager: `~/.config/home-manager/`
