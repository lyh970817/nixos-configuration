#!/usr/bin/env bash

# Keep the workspace dashboard alive if btop is exited with q, Ctrl+C, or a
# process signal. Killing the containing kitty process remains an explicit
# administrative escape hatch.
#
# The single pane shows either this machine's btop or the peer's, flipped by
# Super+B (hyprland.lua). `btop-workspace toggle-host` writes the new choice to
# the state file read at the top of each iteration below and kills the inner
# process, so the switch lands within one iteration without restarting the
# kitty window, the systemd service, or the workspace guard.
#
# The state file is the single source of truth for which host is displayed,
# which is why the fallback paths below write it before falling back rather
# than merely running local btop: the toggle decides its direction from that
# file, so a pane silently demoted to local while the file still said "remote"
# would invert the toggle and cost the user a wasted press.

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/btop-workspace"
host_file="$runtime_dir/dashboard-host"
child_file="$runtime_dir/dashboard-child-pid"
mkdir -p "$runtime_dir"

# Per-machine facts. This script is deployed verbatim as a dotfile and cannot
# be templated, so they arrive through role.env — the shell-sourceable twin of
# role.lua that home/programs/dotfiles.nix generates and monitor-switch.sh
# already reads. HYPR_PEER_HOST is empty when no peer is configured.
# shellcheck source=/dev/null
. "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/role.env" 2> /dev/null || true
peer="${HYPR_PEER_HOST:-}"

# Hyprland does not apply a static fullscreen rule to this silently-created,
# initially-unfocused window. Focus it once after mapping, enter compositor
# fullscreen, then restore the workspace that was active during startup.
# This acts on the kitty window and is independent of what runs inside it, so
# neither the local/remote switch nor a trimmed btop layout affects it.
(
    starting_workspace=$(hyprctl activeworkspace -j | jq -r '.id')

    for _ in {1..20}; do
        dashboard_address=$(hyprctl clients -j | jq -r --argjson pid "$PPID" \
            '.[] | select(.pid == $pid) | .address' | head -1)
        if [ -n "$dashboard_address" ]; then
            # `hyprctl dispatch` evaluates its argument as Lua under the Lua
            # config manager; the legacy dispatcher names no longer parse.
            hyprctl dispatch "hl.dsp.focus({ window = \"address:$dashboard_address\" })"
            hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized" })'
            hyprctl dispatch "hl.dsp.focus({ workspace = $starting_workspace })"
            exit 0
        fi
        sleep 0.1
    done
) &

# Theme and layout follow deliberately opposite machines, and this is the
# first half of that:
#
#   Theme follows the machine DOING THE DISPLAYING — always this one. The pane
#   shares a screen with this machine's windows, so it has to match this
#   machine's dark/light mode whichever host it is monitoring.
#
#   Layout follows the machine BEING MONITORED. The peer's btop runs on the
#   peer and reads the peer's own config, so the trimmed remote layout in
#   home/programs/btop.nix shows up when viewing the laptop from the desktop.
#   That is intended; do not collapse the two rules into one.
#
# The local pane reaches "this machine's mode" by clearing THEME_MODE here, so
# btop's wrapper takes its local-monitor path (Layer A) rather than relying on
# the systemd service environment happening to be empty. The remote pane
# reaches the same answer from the other direction, by setting THEME_MODE
# explicitly over the link — see the theme-hold call below.
unset THEME_MODE

# Truncate rather than delete, as pkgs/screen-record/screen-record.sh does for
# its own state: the only reader is `btop-workspace toggle-host`, which guards
# on `read` succeeding and on the value being numeric, so an empty file reads
# exactly like a missing one and this script never hands a path to rm.
trap ': > "$child_file"' EXIT

# Run the pane's inner process in a subshell that records its own PID and then
# execs, so the recorded PID *is* the process finally running — btop itself,
# or ssh itself — never a surviving wrapper that would leave ssh orphaned and
# still holding the terminal. That is what lets Super+B kill a stuck ssh
# outright instead of waiting for its timeout to expire.
#
# Tracked explicitly rather than located with pgrep -f: that pattern matches
# this script's own ssh command line here, and the incoming session when run
# on the peer, and it has bitten this repository repeatedly.
run_pane() {
    (
        printf '%s\n' "$BASHPID" > "$child_file"
        exec "$@"
    )
}

# Signalling a foreground child makes the shell itself print a "Terminated"
# job-status line, so every toggle-host switch would leave one on screen for
# the quarter second before the next pane draws. Wipe it as soon as the child
# is reaped; anything this loop wants the user to read is printed afterwards.
clear_pane() {
    printf '\033[2J\033[H'
}

while true; do
    target=local
    if [ -r "$host_file" ]; then
        read -r target < "$host_file" || target=local
    fi

    if [ "$target" = remote ] && [ -z "$peer" ]; then
        printf '\033[2J\033[HNo peer machine is configured; showing this machine.\n'
        printf 'local\n' > "$host_file"
        sleep 2
        continue
    fi

    if [ "$target" = remote ]; then
        # This machine's currently applied mode, handed to the peer through
        # theme-hold exactly as the ssh/mosh client wrappers in
        # home/programs/shell.nix do it. theme-mode exists for this (see
        # home/desktop/theming.nix); setting the variable in the remote
        # command line is the portable form, needing no sshd AcceptEnv.
        mode=$(theme-mode 2> /dev/null || echo dark)
        case "$mode" in
            dark | light) ;;
            *) mode=dark ;;
        esac

        # Connecting, connected-and-idle, and dead all look like a static
        # terminal, so say which one this is. btop repaints over it on
        # success; on a hang the message is what stays on screen.
        printf '\033[2J\033[HConnecting to %s ...\n' "$peer"

        # ConnectTimeout bounds an unreachable or asleep peer; the ServerAlive
        # pair bounds a link that dies mid-session, which no connect timeout
        # would ever catch. Deliberately no BatchMode: Tailscale SSH does the
        # authenticating and a check-mode prompt arrives as keyboard-
        # interactive, which BatchMode would turn into a hard failure. Nothing
        # here prompts for a password, and ssh.nix already pins
        # StrictHostKeyChecking=accept-new for the peer.
        run_pane ssh -t \
            -o ConnectTimeout=5 \
            -o ServerAliveInterval=5 \
            -o ServerAliveCountMax=3 \
            "$peer" "theme-hold $mode btop"
        status=$?
        : > "$child_file"
        # A remote TUI killed mid-draw leaves this tty in raw mode.
        stty sane 2> /dev/null || true
        clear_pane

        # ssh reserves 255 for its own failures — refused, timed out, name
        # unresolved, or a session the ServerAlive probes gave up on. Anything
        # else is the remote btop having exited on its own terms (q, status 0),
        # which should respawn remotely.
        #
        # But 255 alone cannot mean "unreachable", because ssh also reports an
        # abnormally torn-down session with it. Measured against this pair:
        # SIGTERM to an ssh still inside connect() exits 143, while the same
        # SIGTERM to an *established* -t session exits 255 — indistinguishable
        # from a refused or dropped connection. Enumerating exit codes is what
        # broke this; the signal number is not the fact we need.
        #
        # So ask the state file instead, which is already the single source of
        # truth for the displayed host. toggle-host writes the new target
        # *before* signalling this child, so by the time this exit is observed
        # the write has landed: a file that no longer says "remote" means the
        # user asked to leave, and this exit is intent, not failure. Fall back
        # only when the file still says "remote" and nobody asked for anything.
        #
        # Resolved exactly as the top of the loop resolves it, so this branch
        # can never disagree with the host the next iteration actually draws.
        after=local
        if [ -r "$host_file" ]; then
            read -r after < "$host_file" || after=local
        fi

        if [ "$after" = remote ] && [ "$status" -eq 255 ]; then
            printf 'local\n' > "$host_file"
            printf 'Cannot reach %s — showing this machine.\n' "$peer"
            notify-send -a "btop dashboard" "$peer unreachable" \
                "Showing this machine instead." || true
            sleep 2
            continue
        fi
    else
        run_pane btop
        : > "$child_file"
        clear_pane
    fi

    sleep 0.25
done
