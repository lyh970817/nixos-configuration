#!/usr/bin/env bash

# Keep the workspace dashboard alive if btop is exited with q, Ctrl+C, or a
# process signal. Killing the containing kitty process remains an explicit
# administrative escape hatch.

# Hyprland does not apply a static fullscreen rule to this silently-created,
# initially-unfocused window. Focus it once after mapping, enter compositor
# fullscreen, then restore the workspace that was active during startup.
(
    starting_workspace=$(hyprctl activeworkspace -j | jq -r '.id')

    for _ in {1..20}; do
        dashboard_address=$(hyprctl clients -j | jq -r --argjson pid "$PPID" \
            '.[] | select(.pid == $pid) | .address' | head -1)
        if [ -n "$dashboard_address" ]; then
            # `hyprctl dispatch` evaluates its argument as Lua under the Lua
            # config manager; the legacy dispatcher names no longer parse.
            # hypr-ipc sends whichever dialect the running compositor speaks;
            # the legacy argv after `--` is TRANSITIONAL (see pkgs/hypr-ipc.nix).
            hypr-ipc dispatch "hl.dsp.focus({ window = \"address:$dashboard_address\" })" \
                -- focuswindow "address:$dashboard_address"
            hypr-ipc dispatch 'hl.dsp.window.fullscreen({ mode = "maximized" })' \
                -- fullscreen 1
            hypr-ipc dispatch "hl.dsp.focus({ workspace = $starting_workspace })" \
                -- workspace "$starting_workspace"
            exit 0
        fi
        sleep 0.1
    done
) &

# The dashboard is part of the desktop environment, so it follows this
# machine's own monitor (Layer A) and must not inherit a session's
# THEME_MODE. Clearing it here makes btop's wrapper take its local-monitor
# path deliberately, rather than relying on the systemd service environment
# happening to be empty.
unset THEME_MODE

while true; do
    btop
    sleep 0.25
done
