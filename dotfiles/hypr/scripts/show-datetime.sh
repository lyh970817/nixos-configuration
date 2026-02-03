#!/usr/bin/env bash

# Get current date and time
current_date=$(date "+%A, %B %d, %Y")
current_time=$(date "+%H:%M:%S")

# Send notification
notify-send "$current_time" "$current_date" --urgency=normal
