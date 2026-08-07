#!/usr/bin/env bash
# Claude Code status line script
# Mirrors the user's Starship prompt style (~/.config/starship.toml):
# directory = bold cyan, git_branch = bold purple ("on  <branch>"),
# git_status = bold yellow "[...]" with Starship's default symbol set
# (yellow, not Starship's stock red: the amber palette maps bright red to its
# darkest brown, which left the repository state unreadable),
# plus Claude Code's own segments: model name and a context usage bar.

set -euo pipefail

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // empty')
[ -z "$cwd" ] && cwd="$PWD"
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
weekly=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
duration_ms=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // empty')

RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD_CYAN=$'\033[1;36m'
BOLD_PURPLE=$'\033[1;35m'
BOLD_RED=$'\033[1;31m'
BOLD_YELLOW=$'\033[1;33m'
GIT_ICON=$''
BOLD_GREEN=$'\033[1;32m'
RED=$'\033[31m'

# --- model segment (first) ---
output="${BOLD_YELLOW} ${model}${RESET}"

git_root=$(git --no-optional-locks -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)

# --- directory segment (Starship: bold cyan, repo-relative or last 3 parts) ---
display_path="$cwd"
case "$display_path" in
  "$HOME") display_path="~" ;;
  "$HOME"/*) display_path="~${display_path#"$HOME"}" ;;
esac

if [ -n "$git_root" ]; then
  repo_name=$(basename "$git_root")
  case "$cwd" in
    "$git_root") display_path="$repo_name" ;;
    "$git_root"/*) display_path="$repo_name/${cwd#"$git_root"/}" ;;
  esac
else
  IFS='/' read -ra parts <<< "$display_path"
  count=${#parts[@]}
  if [ "$count" -gt 3 ]; then
    display_path=$(printf '/%s' "${parts[@]: -3}")
    display_path="${display_path#/}"
  fi
fi

read_only_segment=""
[ ! -w "$cwd" ] && read_only_segment="${RED} 󰌾${RESET}"

output+=" ${DIM}|${RESET} ${BOLD_CYAN}${display_path}${RESET}${read_only_segment}"

# --- git branch + git status segments, cached 5s per repo to avoid slow calls ---
if [ -n "$git_root" ]; then
  cache_file="/tmp/claude-statusline-git-cache-$(printf '%s' "$git_root" | tr '/' '_')"
  now=$(date +%s)
  git_segment=""

  if [ -f "$cache_file" ]; then
    cached_time=$(head -1 "$cache_file" 2>/dev/null || echo 0)
    if [ $((now - cached_time)) -lt 5 ]; then
      git_segment=$(tail -n +2 "$cache_file")
    fi
  fi

  if [ -z "$git_segment" ]; then
    branch=$(git --no-optional-locks -C "$git_root" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git --no-optional-locks -C "$git_root" rev-parse --short HEAD 2>/dev/null)

    conflicted=false; staged=false; modified=false; deleted=false; renamed=false; untracked=false
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      x=${line:0:1}
      y=${line:1:1}
      case "$x$y" in
        "??") untracked=true ;;
        UU|AA|DD|AU|UA|UD|DU) conflicted=true ;;
        *)
          case "$x" in M|A|R|C) staged=true ;; esac
          [ "$x" = "R" ] && renamed=true
          [ "$x" = "D" ] && deleted=true
          [ "$y" = "M" ] && modified=true
          [ "$y" = "D" ] && deleted=true
          ;;
      esac
    done <<< "$(git --no-optional-locks -C "$git_root" status --porcelain=v1 2>/dev/null)"

    stash_count=$(git --no-optional-locks -C "$git_root" stash list 2>/dev/null | wc -l)
    stashed=false
    [ "$stash_count" -gt 0 ] && stashed=true

    ahead=0; behind=0
    upstream=$(git --no-optional-locks -C "$git_root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [ -n "$upstream" ]; then
      counts=$(git --no-optional-locks -C "$git_root" rev-list --left-right --count "HEAD...${upstream}" 2>/dev/null || true)
      ahead=$(printf '%s' "$counts" | awk '{print $1}')
      behind=$(printf '%s' "$counts" | awk '{print $2}')
      [ -z "$ahead" ] && ahead=0
      [ -z "$behind" ] && behind=0
    fi

    status_str=""
    $conflicted && status_str+="="
    $stashed && status_str+='$'
    $deleted && status_str+="✘"
    $renamed && status_str+="»"
    $modified && status_str+="!"
    $staged && status_str+="+"
    $untracked && status_str+="?"
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      status_str+="⇕"
    elif [ "$ahead" -gt 0 ]; then
      status_str+="⇡"
    elif [ "$behind" -gt 0 ]; then
      status_str+="⇣"
    fi

    git_segment=""
    [ -n "$branch" ] && git_segment=" on ${BOLD_PURPLE}${GIT_ICON} ${branch}${RESET}"
    [ -n "$status_str" ] && git_segment+=" ${BOLD_YELLOW}[${status_str}]${RESET}"

    printf '%s\n%s' "$now" "$git_segment" > "$cache_file" 2>/dev/null || true
  fi

  output+="$git_segment"
fi

# --- context usage bar ---
if [ -n "$used" ]; then
  used_int=${used%.*}
  [ -z "$used_int" ] && used_int=0
  if [ "$used_int" -ge 90 ]; then
    bar_color="$BOLD_RED"
  elif [ "$used_int" -ge 70 ]; then
    bar_color="$BOLD_YELLOW"
  else
    bar_color="$BOLD_GREEN"
  fi

  bar_width=10
  filled=$(( used_int * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  empty=$(( bar_width - filled ))

  bar="${bar_color}"
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  bar+="${RESET} ${used_int}%"

  output+=" ${DIM}|${RESET} ${bar}"
fi

# --- weekly (7-day) rate limit segment ---
if [ -n "$weekly" ]; then
  weekly_int=${weekly%.*}
  [ -z "$weekly_int" ] && weekly_int=0
  if [ "$weekly_int" -ge 90 ]; then
    weekly_color="$BOLD_RED"
  elif [ "$weekly_int" -ge 70 ]; then
    weekly_color="$BOLD_YELLOW"
  else
    weekly_color="$BOLD_GREEN"
  fi
  output+=" ${DIM}|${RESET} ${DIM}7d${RESET} ${weekly_color}${weekly_int}%${RESET}"
fi

# --- duration segment ---
if [ -n "$duration_ms" ] && [ "$duration_ms" -gt 0 ]; then
  duration_s=$(( duration_ms / 1000 ))
  mins=$(( duration_s / 60 ))
  secs=$(( duration_s % 60 ))
  if [ "$mins" -gt 0 ]; then
    output+=" ${DIM}|${RESET} ${DIM}${mins}m ${secs}s${RESET}"
  else
    output+=" ${DIM}|${RESET} ${DIM}${secs}s${RESET}"
  fi
fi

printf '%s\n' "$output"
