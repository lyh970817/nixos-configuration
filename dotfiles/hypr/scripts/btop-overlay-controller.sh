#!/usr/bin/env bash

# Keep workspace 10's ordinary windows in a full-scale special workspace above
# the protected btop dashboard. The event socket catches windows regardless of
# whether they were launched, restored, or moved onto workspace 10.

base_workspace=10
overlay_name=btop-overlay
overlay_workspace="special:$overlay_name"
dashboard_class=Alacritty-btop
instance_dir="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE"

# Only one event consumer may reconcile the overlay for this compositor
# instance. A duplicate could observe the same state and toggle it twice.
exec 9>"$instance_dir/btop-overlay-controller.lock"
flock -n 9 || exit 0

overlay_has_clients() {
    hyprctl clients -j | jq -e --arg workspace "$overlay_workspace" \
        'any(.[]; .workspace.name == $workspace)' >/dev/null
}

overlay_is_visible() {
    hyprctl monitors -j | jq -e --arg workspace "$overlay_workspace" \
        'any(.[]; .specialWorkspace.name == $workspace)' >/dev/null
}

focus_overlay_client() {
    overlay_address=$(
        hyprctl clients -j | jq -r --arg workspace "$overlay_workspace" \
            '[.[] | select(.workspace.name == $workspace)]
             | sort_by(.focusHistoryID) | first | .address // empty'
    )
    if [ -n "$overlay_address" ]; then
        hyprctl dispatch focuswindow "address:$overlay_address" >/dev/null
    fi
}

route_base_clients() {
    while IFS= read -r address; do
        [ -n "$address" ] || continue
        hyprctl dispatch movetoworkspacesilent \
            "$overlay_workspace,address:$address" >/dev/null
    done < <(
        hyprctl clients -j | jq -r \
            --arg workspace "$base_workspace" \
            --arg dashboard "$dashboard_class" \
            '.[] | select(.workspace.name == $workspace and .class != $dashboard) | .address'
    )
}

sync_overlay() {
    route_base_clients

    active_workspace=$(hyprctl activeworkspace -j | jq -r '.name')
    if [ "$active_workspace" = "$base_workspace" ] && overlay_has_clients; then
        if ! overlay_is_visible; then
            hyprctl dispatch togglespecialworkspace "$overlay_name" >/dev/null
        fi

        # The special workspace normally owns focus. Correct it explicitly if
        # a click through a gap or an external dispatcher reaches btop anyway.
        if [ "$(hyprctl activewindow -j | jq -r '.class // empty')" = "$dashboard_class" ]; then
            focus_overlay_client
        fi
    elif overlay_is_visible; then
        hyprctl dispatch togglespecialworkspace "$overlay_name" >/dev/null
    fi
}

sync_overlay

# Reconnect after a compositor reload or an IPC interruption.
while true; do
    event_socket="$instance_dir/.socket2.sock"
    if [ -S "$event_socket" ]; then
        while IFS= read -r _event; do
            sync_overlay
        done < <(nc -U "$event_socket" 9>&-)
    fi
    sleep 1
done
