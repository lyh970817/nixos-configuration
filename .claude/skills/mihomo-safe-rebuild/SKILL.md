---
name: mihomo-safe-rebuild
description: Safely test mihomo proxy configuration changes with automatic rollback. Use when modifying mihomo-config.yaml for debugging connectivity issues, enabling tun mode, changing proxy settings, or any mihomo config change that risks breaking internet connectivity.
---

# Mihomo Safe Rebuild

Dead man's switch workflow for testing mihomo configuration changes on NixOS. Automatically rolls back and rebuilds if the new config breaks connectivity.

## Workflow

1. Make the desired changes to `mihomo-config.yaml`
2. Run the safe rebuild script
3. Check the connectivity log output
4. Cancel the rollback timer if connectivity is good, or wait for auto-rollback if not

## Usage

Run the bundled script as root:

```bash
sudo scripts/mihomo-safe-rebuild.sh          # 2-min rollback timeout (default)
sudo scripts/mihomo-safe-rebuild.sh 180      # custom timeout in seconds
```

The script will:
- Back up the current working `mihomo-config.yaml`
- Start a background rollback timer that restores the backup and runs `nixos-rebuild` after the timeout
- Start a connectivity monitor that curls google.com every 5s, logging results to `/tmp/mihomo-tun-connectivity.log`
- Run `nixos-rebuild switch --flake .#andongni --impure`
- Wait 15s then print the connectivity log

If connectivity looks good, cancel the rollback:

```bash
sudo scripts/mihomo-safe-rebuild.sh cancel
```

If connectivity is broken, do nothing — the rollback fires automatically.

## Key Details

- Config path: `mihomo-config.yaml` in the repo root
- NixOS copies the config into the Nix store at build time (path literal), so `nixos-rebuild` is required for changes to take effect — a service restart alone is not enough
- Always use `--impure` flag because `mihomo-config.yaml` contains secrets and is not tracked in git
- Connectivity log: `/tmp/mihomo-tun-connectivity.log`

## Common Issues

- **Tun mode with `stack: mixed` breaks all connectivity** — use `stack: gvisor` instead
- **`external-controller` missing** — add `external-controller: 127.0.0.1:9090` to enable the metacubexd dashboard at `http://127.0.0.1:9090/ui/`
- **Config changes not taking effect after restart** — must run `nixos-rebuild`, not just `systemctl restart mihomo`
