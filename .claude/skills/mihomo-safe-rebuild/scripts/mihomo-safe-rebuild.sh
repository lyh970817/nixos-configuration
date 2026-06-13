#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="/home/andongni/Yandex.Disk/System/nixos-configuration"
CONFIG="$REPO_DIR/mihomo-config.yaml"
BACKUP="$CONFIG.bak"
CONNECTIVITY_LOG="/tmp/mihomo-tun-connectivity.log"
ROLLBACK_PIDFILE="/tmp/mihomo-rollback.pid"
MONITOR_PIDFILE="/tmp/mihomo-monitor.pid"
ROLLBACK_TIMEOUT="${1:-120}"

cleanup_old() {
    for pidfile in "$ROLLBACK_PIDFILE" "$MONITOR_PIDFILE"; do
        if [[ -f "$pidfile" ]]; then
            local pid
            pid=$(<"$pidfile")
            kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null || true
            rm -f "$pidfile"
        fi
    done
}

cancel_rollback() {
    echo "Cancelling rollback timer and connectivity monitor..."
    cleanup_old
    echo "Done. Config is live."
}

main() {
    if [[ "${1:-}" == "cancel" ]]; then
        cancel_rollback
        exit 0
    fi

    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root (sudo)."
        exit 1
    fi

    cleanup_old

    # Step 1: Back up working config
    echo "[1/4] Backing up current config..."
    cp "$CONFIG" "$BACKUP"
    echo "       Saved to $BACKUP"

    # Step 2: Start rollback timer
    echo "[2/4] Starting rollback timer (${ROLLBACK_TIMEOUT}s)..."
    (
        sleep "$ROLLBACK_TIMEOUT"
        echo ""
        echo "=== ROLLBACK TRIGGERED ==="
        echo "Restoring backup config and rebuilding..."
        cp "$BACKUP" "$CONFIG"
        nixos-rebuild switch --flake "$REPO_DIR#andongni" --impure 2>&1
        echo "=== ROLLBACK COMPLETE ==="
    ) &
    echo "$!" > "$ROLLBACK_PIDFILE"
    echo "       PID: $! — will restore config in ${ROLLBACK_TIMEOUT}s if not cancelled"

    # Step 3: Start connectivity monitor
    echo "[3/4] Starting connectivity monitor (logging to $CONNECTIVITY_LOG)..."
    : > "$CONNECTIVITY_LOG"
    (
        for i in $(seq 1 30); do
            printf "%s - attempt %d: " "$(date +%H:%M:%S)" "$i" >> "$CONNECTIVITY_LOG"
            curl -s -o /dev/null -w "http_code=%{http_code} time=%{time_total}s" \
                --max-time 5 https://www.google.com >> "$CONNECTIVITY_LOG" 2>&1 \
                || printf " FAILED" >> "$CONNECTIVITY_LOG"
            echo "" >> "$CONNECTIVITY_LOG"
            sleep 5
        done
    ) &
    echo "$!" > "$MONITOR_PIDFILE"

    # Step 4: Rebuild
    echo "[4/4] Rebuilding NixOS..."
    echo ""
    nixos-rebuild switch --flake "$REPO_DIR#andongni" --impure 2>&1
    echo ""

    # Show connectivity results after a short wait
    echo "Rebuild done. Waiting 15s to collect connectivity data..."
    sleep 15
    echo ""
    echo "=== Connectivity Log ==="
    cat "$CONNECTIVITY_LOG"
    echo ""
    echo "If connectivity looks good, run:"
    echo "  sudo $0 cancel"
    echo ""
    echo "Otherwise, rollback will trigger automatically in ~$((ROLLBACK_TIMEOUT - 30))s."
}

main "$@"
