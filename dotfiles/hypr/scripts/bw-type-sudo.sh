#!/usr/bin/env bash

# Load Bitwarden session from file
BW_SESSION_FILE="$HOME/.cache/bw-session"

if [ -f "$BW_SESSION_FILE" ]; then
  export BW_SESSION=$(cat "$BW_SESSION_FILE")
else
  notify-send -u critical "Bitwarden" "🔒 No session found. Run 'bwu' in a terminal first."
  exit 1
fi

# Check if session is still valid
if ! bw unlock --check &>/dev/null; then
  notify-send -u critical "Bitwarden" "🔒 Session expired. Run 'bwu' in a terminal to unlock."
  exit 1
fi

# Notify that we're fetching the password
notify-send "Bitwarden" "🔑 Fetching password..."

# Get password
password=$(bw get password "sudo" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$password" ]; then
  wtype "$password"
  notify-send "Bitwarden" "✓ Password typed successfully"
else
  notify-send -u critical "Bitwarden" "❌ Failed to get password for 'sudo'"
  exit 1
fi
