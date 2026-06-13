#!/usr/bin/env bash
# Claude Code status line script
# Produces a single-line colored status bar

set -euo pipefail

input=$(cat)

# --- Parse JSON input ---
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // "~"')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

# --- ANSI colors ---
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'

# --- Folder name ---
folder=$(basename "$cwd")

# --- Git info with 5s cache ---
cache_file="/tmp/claude-statusline-git-cache"
cache_key="$cwd"
git_info=""

get_git_info() {
  if ! git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    echo ""
    return
  fi
  local branch staged modified
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  staged=$(git -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l)
  modified=$(git -C "$cwd" diff --numstat 2>/dev/null | wc -l)

  local result=" ${DIM}|${RESET} ${BOLD}${branch}${RESET}"
  [ "$staged" -gt 0 ] && result+=" ${GREEN}+${staged}${RESET}"
  [ "$modified" -gt 0 ] && result+=" ${YELLOW}~${modified}${RESET}"
  echo "$result"
}

# Use cache if fresh (< 5 seconds)
if [ -f "$cache_file" ]; then
  cached_key=$(head -1 "$cache_file" 2>/dev/null || true)
  cached_time=$(sed -n '2p' "$cache_file" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ "$cached_key" = "$cache_key" ] && [ $((now - cached_time)) -lt 5 ]; then
    git_info=$(tail -n +3 "$cache_file")
  fi
fi

if [ -z "$git_info" ]; then
  git_info=$(get_git_info)
  printf '%s\n%s\n%s' "$cache_key" "$(date +%s)" "$git_info" > "$cache_file" 2>/dev/null || true
fi

# --- Progress bar ---
bar_width=10
filled=$(( used_pct * bar_width / 100 ))
empty=$(( bar_width - filled ))

if [ "$used_pct" -lt 70 ]; then
  bar_color="$GREEN"
elif [ "$used_pct" -lt 90 ]; then
  bar_color="$YELLOW"
else
  bar_color="$RED"
fi

bar="${bar_color}"
for ((i=0; i<filled; i++)); do bar+="█"; done
for ((i=0; i<empty; i++)); do bar+="░"; done
bar+="${RESET} ${used_pct}%"

# --- Cost & duration ---
meta=""
if [ "$(echo "$cost > 0" | bc 2>/dev/null || echo 0)" = "1" ]; then
  meta+=" ${DIM}\$${cost}${RESET}"
fi
if [ "$duration_ms" -gt 0 ]; then
  duration_s=$(( duration_ms / 1000 ))
  mins=$(( duration_s / 60 ))
  secs=$(( duration_s % 60 ))
  if [ "$mins" -gt 0 ]; then
    meta+=" ${DIM}${mins}m ${secs}s${RESET}"
  fi
fi

# --- Add separators ---
sep=" ${DIM}|${RESET} "
[ -n "$meta" ] && meta="${sep}${meta# }"

# --- Output single line ---
line="${CYAN}${BOLD}[${model}]${RESET} ${folder}${git_info}${sep}${bar}${meta}"
printf '%s\n' "$line"
