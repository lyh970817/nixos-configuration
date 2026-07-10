#!/usr/bin/env bash

# Keep the workspace dashboard alive if btop is exited with q, Ctrl+C, or a
# process signal. Killing the containing Alacritty process remains an explicit
# administrative escape hatch.
while true; do
    btop
    sleep 0.25
done
