#!/usr/bin/env bash

# Prevent ordinary window-management shortcuts from changing the dedicated
# btop dashboard. The same shortcuts continue to work for every other window.
if btop-workspace is-dashboard-active; then
    exit 0
fi

# Workspace 10 is reserved for the managed dashboard while its guard is locked.
if [ "${1:-}" = "movetoworkspace" ] && [ "${2:-}" = "10" ] && btop-workspace is-locked; then
    exit 0
fi

# Under Hyprland's Lua config manager `hyprctl dispatch` no longer takes a
# legacy dispatcher name: its argument is evaluated as Lua, so
# `hyprctl dispatch killactive` is a syntax error rather than an action. The
# binds still speak the legacy vocabulary (it reads better in hyprland.lua and
# keeps the guards above working on plain words), so translate here.
#
# Unknown verbs are a hard error rather than a pass-through: a dispatcher that
# silently does nothing is the exact failure this file exists to make loud.
verb=${1:-}
shift || true

case "$verb" in
killactive) expr='hl.dsp.window.close()' ;;
forcekillactive) expr='hl.dsp.window.kill()' ;;
togglefloating) expr='hl.dsp.window.float({ action = "toggle" })' ;;
pseudo) expr='hl.dsp.window.pseudo()' ;;
fullscreen)
    # Legacy `fullscreen 1` is maximize; `fullscreen 0` is real fullscreen.
    case "${1:-0}" in
    1) expr='hl.dsp.window.fullscreen({ mode = "maximized" })' ;;
    *) expr='hl.dsp.window.fullscreen({ mode = "fullscreen" })' ;;
    esac
    ;;
layoutmsg) expr="hl.dsp.layout(\"${1:-}\")" ;;
alterzorder) expr="hl.dsp.window.alter_zorder({ mode = \"${1:-top}\" })" ;;
swapwindow)
    case "${1:-}" in
    l) dir=left ;;
    r) dir=right ;;
    u) dir=up ;;
    d) dir=down ;;
    *) dir="${1:-}" ;;
    esac
    expr="hl.dsp.window.swap({ direction = \"$dir\" })"
    ;;
moveactive) expr="hl.dsp.window.move({ x = ${1:-0}, y = ${2:-0}, relative = true })" ;;
resizeactive) expr="hl.dsp.window.resize({ x = ${1:-0}, y = ${2:-0}, relative = true })" ;;
movetoworkspace) expr="hl.dsp.window.move({ workspace = ${1:-1} })" ;;
*)
    echo "protected-dispatch.sh: no Lua translation for '$verb'" >&2
    exit 2
    ;;
esac

exec hyprctl dispatch "$expr"
