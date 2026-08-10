#!/usr/bin/env bash

# Keep the dedicated btop dashboard fixed on workspace 10.
if btop-workspace is-dashboard-active; then
    exit 0
fi

if btop-workspace is-locked; then
    exit 0
fi

# Get the active window address
window=$(hyprctl activewindow -j | jq -r '.address')

# Check if window is floating
is_floating=$(hyprctl activewindow -j | jq -r '.floating')

# If it was floating, make it tiled. `hyprctl dispatch` evaluates its argument
# as Lua under the Lua config manager, so the legacy dispatcher names are gone;
# hypr-ipc sends whichever dialect the running compositor speaks. The legacy
# argv after `--` is TRANSITIONAL (see pkgs/hypr-ipc.nix).
if [ "$is_floating" = "true" ]; then
    hypr-ipc dispatch "hl.dsp.window.float({ action = \"toggle\", window = \"address:$window\" })" \
        -- togglefloating "address:$window"
fi

# Move to workspace 10 without following it (the legacy "silent" variant).
hypr-ipc dispatch 'hl.dsp.window.move({ workspace = 10, follow = false })' \
    -- movetoworkspacesilent 10
