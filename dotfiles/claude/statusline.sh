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
BOLD_YELLOW=$'\033[1;33m'
GIT_ICON=$''
INVERSE=$'\033[7m'

# Severity ramp for the usage meters. The amber palette offers no usable hue
# axis, so severity rides on luminance instead: muted -> accent -> bright. Every
# step is a bright-slot code because the light theme collapses those to a single
# grey, which flattens the ramp but never inverts it. Plain 31/32 inverted it in
# both themes, which is what this replaces.
USAGE_LOW=$'\033[1;31m'
USAGE_WARN=$'\033[1;33m'
USAGE_HIGH=$'\033[1;32m'

# Picks the ramp step for a percentage.
usage_color() {
  if [ "$1" -ge 90 ]; then
    printf '%s' "$USAGE_HIGH"
  elif [ "$1" -ge 70 ]; then
    printf '%s' "$USAGE_WARN"
  else
    printf '%s' "$USAGE_LOW"
  fi
}

# Renders a percentage. Past the critical step it switches to reverse video and
# gains a "!", so the state carries without depending on colour at all.
usage_label() {
  if [ "$1" -ge 90 ]; then
    printf '%s !%s%% %s' "$INVERSE" "$1" "$RESET"
  else
    printf '%s%s%%%s' "$2" "$1" "$RESET"
  fi
}

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

# Starship stocks this as plain red, which the amber palette renders as its
# border tone -- invisible. Accent amber plus the lock glyph makes the state
# readable without leaning on a hue.
read_only_segment=""
[ ! -w "$cwd" ] && read_only_segment="${BOLD_YELLOW} 󰌾${RESET}"

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
  bar_color=$(usage_color "$used_int")

  bar_width=10
  filled=$(( used_int * bar_width / 100 ))
  [ "$filled" -gt "$bar_width" ] && filled=$bar_width
  empty=$(( bar_width - filled ))

  bar="${bar_color}"
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done
  bar+="${RESET} $(usage_label "$used_int" "$bar_color")"

  output+=" ${DIM}|${RESET} ${bar}"
fi

# --- weekly (7-day) rate limit segment ---
if [ -n "$weekly" ]; then
  weekly_int=${weekly%.*}
  [ -z "$weekly_int" ] && weekly_int=0
  weekly_color=$(usage_color "$weekly_int")
  output+=" ${DIM}|${RESET} ${DIM}7d${RESET} $(usage_label "$weekly_int" "$weekly_color")"
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
