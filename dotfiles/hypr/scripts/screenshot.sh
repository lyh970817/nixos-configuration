#!/usr/bin/env bash

# Take a screenshot and both save it to ~/Pictures/Screenshots and copy it to
# the Wayland clipboard. Two modes:
#   full   - the focused monitor (the "current screen")
#   region - an interactively selected area (via slurp)
# Usage: screenshot.sh {full|region}

set -euo pipefail

mode="${1:-full}"

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$dir"
# date is safe here (plain bash, not a workflow script); use a sortable stamp.
file="$dir/screenshot_$(date +'%Y-%m-%d_%H-%M-%S').png"

case "$mode" in
  full)
    # grim with no -o composites every output into one image; restrict it to the
    # focused monitor so "current screen" means the one under the cursor/focus.
    output="$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')"
    if [ -n "$output" ]; then
      grim -o "$output" "$file"
    else
      grim "$file"
    fi
    ;;
  region)
    # slurp exits non-zero when the selection is cancelled (Esc); bail quietly
    # without leaving an empty file or a stale clipboard entry.
    if ! geometry="$(slurp)"; then
      exit 0
    fi
    grim -g "$geometry" "$file"
    ;;
  *)
    echo "Usage: screenshot.sh {full|region}" >&2
    exit 1
    ;;
esac

# Copy the saved image to the clipboard as well as keeping the file on disk.
wl-copy --type image/png < "$file"

if command -v notify-send > /dev/null; then
  notify-send -h string:x-canonical-private-synchronous:screenshot \
    "Screenshot" "Saved to $file and copied to clipboard"
fi
