#!/usr/bin/env bash

set -euo pipefail

readonly protected_workspace=10
readonly runtime_dir="${XDG_RUNTIME_DIR:?}/btop-workspace"
readonly lock_file="$runtime_dir/locked"
readonly dashboard_file="$runtime_dir/dashboard-address"
readonly last_workspace_file="$runtime_dir/last-normal-workspace"
readonly origins_dir="$runtime_dir/origins"

mkdir -p "$runtime_dir" "$origins_dir"

active_workspace() {
    hyprctl activeworkspace -j | jq -r '.id'
}

is_locked() {
    [ -e "$lock_file" ]
}

dashboard_pid() {
    systemctl --user show --property MainPID --value btop-dashboard.service
}

register_dashboard() {
    local address=$1
    local expected_pid
    local actual_pid

    expected_pid=$(dashboard_pid)
    actual_pid=$(hyprctl clients -j | jq -r --arg address "$address" \
        '.[] | select(.address == $address) | .pid')

    if [ "$expected_pid" != "0" ] && [ "$actual_pid" = "$expected_pid" ]; then
        printf '%s\n' "$address" > "$dashboard_file"
        return 0
    fi

    return 1
}

is_dashboard() {
    local address=$1
    local registered=""

    if [ -r "$dashboard_file" ]; then
        read -r registered < "$dashboard_file"
    fi

    [ "$address" = "$registered" ] || register_dashboard "$address"
}

last_normal_workspace() {
    local workspace=1

    if [ -r "$last_workspace_file" ]; then
        read -r workspace < "$last_workspace_file"
    fi

    if ! [[ "$workspace" =~ ^[0-9]+$ ]] || [ "$workspace" -eq "$protected_workspace" ]; then
        workspace=1
    fi

    printf '%s\n' "$workspace"
}

remember_workspace() {
    local workspace=$1

    if [[ "$workspace" =~ ^[0-9]+$ ]] && [ "$workspace" -ne "$protected_workspace" ]; then
        printf '%s\n' "$workspace" > "$last_workspace_file"
    fi
}

origin_file() {
    printf '%s/%s\n' "$origins_dir" "${1#0x}"
}

remember_origin() {
    local address=$1
    local workspace=$2

    if [[ "$workspace" =~ ^[0-9]+$ ]] && [ "$workspace" -ne "$protected_workspace" ]; then
        printf '%s\n' "$workspace" > "$(origin_file "$address")"
    fi
}

window_origin() {
    local file
    file=$(origin_file "$1")
    [ -r "$file" ] && head -n 1 "$file"
}

forget_origin() {
    rm -f "$(origin_file "$1")"
}

reject_window() {
    local address=$1
    local destination=${2:-}

    if ! [[ "$destination" =~ ^[0-9]+$ ]] || [ "$destination" -eq "$protected_workspace" ]; then
        destination=$(last_normal_workspace)
    fi

    local dashboard_address=""
    if [ -r "$dashboard_file" ]; then
        read -r dashboard_address < "$dashboard_file"
    fi

    hyprctl dispatch movetoworkspacesilent "$destination,address:$address" >/dev/null
    if [ -n "$dashboard_address" ] && [ "$(active_workspace)" = "$protected_workspace" ]; then
        hyprctl dispatch focuswindow "address:$dashboard_address" >/dev/null
    fi
}

reconcile() {
    local fallback
    fallback=$(last_normal_workspace)

    while read -r address; do
        if ! is_dashboard "$address"; then
            reject_window "$address" "$(window_origin "$address" || printf '%s\n' "$fallback")"
            forget_origin "$address"
        fi
    done < <(hyprctl clients -j | jq -r --argjson workspace "$protected_workspace" \
        '.[] | select(.workspace.id == $workspace) | .address')
}

run_daemon() {
    local socket
    local event
    local payload
    local address
    local workspace
    local previous
    declare -A known_workspaces=()

    : > "$lock_file"
    rm -f "$dashboard_file"
    rm -f "$origins_dir"/*
    remember_workspace "$(active_workspace)"

    while read -r address workspace; do
        known_workspaces["$address"]=$workspace
    done < <(hyprctl clients -j | jq -r '.[] | "\(.address) \(.workspace.id)"')

    reconcile

    while true; do
        socket="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE:?}/.socket2.sock"
        while IFS= read -r event; do
            case "$event" in
                workspacev2\>\>*)
                    payload=${event#*>>}
                    workspace=${payload%%,*}
                    remember_workspace "$workspace"
                    ;;
                openwindow\>\>*|openwindowv2\>\>*)
                    payload=${event#*>>}
                    address=${payload%%,*}
                    address=${address#0x}
                    address="0x$address"
                    workspace=$(hyprctl clients -j | jq -r --arg address "$address" \
                        '.[] | select(.address == $address) | .workspace.id')
                    known_workspaces["$address"]=$workspace
                    if is_locked && [ "$workspace" = "$protected_workspace" ] && ! is_dashboard "$address"; then
                        reject_window "$address"
                        forget_origin "$address"
                    fi
                    ;;
                movewindow\>\>*|movewindowv2\>\>*)
                    payload=${event#*>>}
                    address=${payload%%,*}
                    address=${address#0x}
                    address="0x$address"
                    workspace=$(hyprctl clients -j | jq -r --arg address "$address" \
                        '.[] | select(.address == $address) | .workspace.id')
                    previous=${known_workspaces["$address"]:-}
                    if is_dashboard "$address"; then
                        if [ "$workspace" != "$protected_workspace" ]; then
                            hyprctl dispatch movetoworkspacesilent "$protected_workspace,address:$address" >/dev/null
                            known_workspaces["$address"]=$protected_workspace
                        fi
                    elif is_locked && [ "$workspace" = "$protected_workspace" ]; then
                        reject_window "$address" "$previous"
                        forget_origin "$address"
                    else
                        if [ "$workspace" = "$protected_workspace" ]; then
                            remember_origin "$address" "$previous"
                        else
                            forget_origin "$address"
                        fi
                        known_workspaces["$address"]=$workspace
                    fi
                    ;;
                closewindow\>\>*)
                    address=${event#*>>}
                    address=${address#0x}
                    address="0x$address"
                    unset 'known_workspaces[$address]'
                    forget_origin "$address"
                    ;;
            esac
        done < <(socat -U - "UNIX-CONNECT:$socket")
        sleep 1
        reconcile
    done
}

case "${1:-}" in
    daemon)
        run_daemon
        ;;
    lock)
        : > "$lock_file"
        reconcile
        notify-send -a "btop workspace" "Workspace 10 locked" || true
        ;;
    unlock)
        if [ "$(active_workspace)" = "$protected_workspace" ]; then
            printf 'Workspace 10 can only be unlocked from another workspace.\n' >&2
            exit 1
        fi
        rm -f "$lock_file"
        notify-send -a "btop workspace" "Workspace 10 unlocked until the guard restarts" || true
        ;;
    status)
        if is_locked; then
            printf 'locked\n'
        else
            printf 'unlocked\n'
        fi
        ;;
    is-locked)
        is_locked
        ;;
    exec)
        shift
        if is_locked && [ "$(active_workspace)" = "$protected_workspace" ]; then
            exit 0
        fi
        exec "$@"
        ;;
    *)
        printf 'Usage: btop-workspace {lock|unlock|status}\n' >&2
        exit 2
        ;;
esac
