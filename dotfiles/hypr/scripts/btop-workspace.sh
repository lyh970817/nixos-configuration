#!/usr/bin/env bash

set -euo pipefail

readonly protected_workspace=10
readonly runtime_dir="${XDG_RUNTIME_DIR:?}/btop-workspace"
readonly lock_file="$runtime_dir/locked"
readonly dashboard_file="$runtime_dir/dashboard-address"
# Which machine's btop the dashboard pane shows ("local" or "remote"), and the
# PID of the process currently drawing it. Both are the interface to the loop
# in btop-dashboard.sh; see toggle-host below.
readonly host_file="$runtime_dir/dashboard-host"
readonly child_pid_file="$runtime_dir/dashboard-child-pid"
readonly last_workspace_file="$runtime_dir/last-normal-workspace"
readonly origins_dir="$runtime_dir/origins"

mkdir -p "$runtime_dir" "$origins_dir"

active_workspace() {
    hyprctl activeworkspace -j | jq -r '.id'
}

normalize_address() {
    printf '0x%s\n' "${1#0x}"
}

window_workspace() {
    hyprctl clients -j | jq -r --arg address "$1" \
        '.[] | select(.address == $address) | .workspace.id'
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

restore_dashboard() {
    local address=$1
    local starting_workspace
    local fullscreen

    starting_workspace=$(active_workspace)
    # `hyprctl dispatch` evaluates its argument as Lua under the Lua config
    # manager; the legacy dispatcher names no longer parse. `follow = false` is
    # the movetoworkspacesilent variant.
    hyprctl dispatch \
        "hl.dsp.window.move({ workspace = $protected_workspace, follow = false, window = \"address:$address\" })" \
        > /dev/null
    fullscreen=$(hyprctl clients -j | jq -r --arg address "$address" \
        '.[] | select(.address == $address) | .fullscreen')

    if [ "$starting_workspace" = "$protected_workspace" ] || [ "$fullscreen" != "1" ]; then
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" > /dev/null
    fi
    if [ "$fullscreen" != "1" ]; then
        hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized" })' > /dev/null
    fi
    if [ "$starting_workspace" != "$protected_workspace" ]; then
        hyprctl dispatch "hl.dsp.focus({ workspace = $starting_workspace })" > /dev/null
    fi
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

    hyprctl dispatch \
        "hl.dsp.window.move({ workspace = $destination, follow = false, window = \"address:$address\" })" \
        > /dev/null
    if [ -n "$dashboard_address" ] && [ "$(active_workspace)" = "$protected_workspace" ]; then
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$dashboard_address\" })" > /dev/null
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
    # The dashboard comes back up showing this machine on every fresh
    # graphical session: booting into a pane pointed at a laptop that is shut
    # in a bag is a bad default, and the remote target is only ever a
    # deliberate keypress away. Reset here, in the once-per-session daemon
    # startup, rather than in btop-dashboard.sh — the theme hooks in
    # home/desktop/theming.nix try-restart btop-dashboard.service on every
    # dark/light switch, so resetting there would silently yank the pane back
    # to this machine every time the theme changed, and would throw away the
    # peer reconnect that carries the new mode across.
    printf 'local\n' > "$host_file"
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
                    address=$(normalize_address "${payload%%,*}")
                    workspace=$(window_workspace "$address")
                    known_workspaces["$address"]=$workspace
                    if is_locked && [ "$workspace" = "$protected_workspace" ] && ! is_dashboard "$address"; then
                        reject_window "$address"
                        forget_origin "$address"
                    fi
                    ;;
                movewindow\>\>*|movewindowv2\>\>*)
                    payload=${event#*>>}
                    address=$(normalize_address "${payload%%,*}")
                    workspace=$(window_workspace "$address")
                    previous=${known_workspaces["$address"]:-}
                    if is_dashboard "$address"; then
                        if [ "$workspace" != "$protected_workspace" ]; then
                            restore_dashboard "$address"
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
                    address=$(normalize_address "${event#*>>}")
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
    toggle-host)
        # Flip the dashboard pane between this machine and the peer.
        #
        # The current target is resolved from the state file and from nothing
        # else — never by probing the connection or inspecting the running
        # process. That is what keeps this usable as the rescue: when the pane
        # is wedged on an ssh hung mid-connect, the file still says "remote",
        # so the flip decides on "local" and kills the ssh immediately instead
        # of blocking on the very connection it is trying to escape.
        #
        # It also makes the auto-fallback in btop-dashboard.sh load-bearing:
        # that path writes "local" before falling back, so a pane demoted by a
        # connect timeout or a dead link leaves the file agreeing with the
        # screen. Were it not to, this toggle would invert and the user would
        # have to press twice.
        current=local
        if [ -r "$host_file" ] && read -r stored < "$host_file"; then
            current=$stored
        fi
        case "$current" in
            remote) next=local ;;
            # Anything that is not exactly "remote" is displayed as local by
            # the loop, so it has to toggle as local too.
            *) next=remote ;;
        esac

        # Write before killing: the loop re-reads this file as soon as its
        # child exits, so the new target has to already be on disk.
        printf '%s\n' "$next" > "$host_file"

        # btop-dashboard.sh execs over the subshell that records this PID, so
        # it is the inner process itself — btop, or ssh — and the signal
        # reaches ssh directly instead of orphaning it behind a wrapper still
        # holding the terminal. SIGTERM rather than SIGINT: ssh turns SIGINT
        # into its own exit 255, which the loop would then misreport as an
        # unreachable peer on every deliberate switch back to this machine.
        if [ -r "$child_pid_file" ] && read -r child < "$child_pid_file"; then
            if [[ "$child" =~ ^[0-9]+$ ]]; then
                kill "$child" 2> /dev/null || true
            fi
        fi
        ;;
    is-dashboard-active)
        is_dashboard "$(hyprctl activewindow -j | jq -r '.address // ""')"
        ;;
    exec)
        shift
        if is_locked && [ "$(active_workspace)" = "$protected_workspace" ]; then
            exit 0
        fi
        exec "$@"
        ;;
    *)
        printf 'Usage: btop-workspace {lock|unlock|status|toggle-host}\n' >&2
        exit 2
        ;;
esac
