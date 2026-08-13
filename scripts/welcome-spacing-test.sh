#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
welcome_source="$repo_root/home/programs/print_welcome.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

run_case() {
  local name=$1
  local fastfetch_status=$2
  local poem_status=$3
  local fastfetch_output=$4
  local poem_output=$5

  FASTFETCH_STATUS=$fastfetch_status \
    POEM_STATUS=$poem_status \
    FASTFETCH_OUTPUT=$fastfetch_output \
    POEM_OUTPUT=$poem_output \
    WELCOME_SOURCE=$welcome_source \
    zsh -f > "$test_dir/$name.actual" <<'ZSH'
fastfetch() {
  printf %s "$FASTFETCH_OUTPUT"
  return "$FASTFETCH_STATUS"
}
print_welcome_poem() {
  printf %s "$POEM_OUTPUT"
  return "$POEM_STATUS"
}
source "$WELCOME_SOURCE"
print_shell_welcome
ZSH
}

assert_output() {
  local name=$1
  local expected=$2
  printf %s "$expected" > "$test_dir/$name.expected"
  if ! cmp -s "$test_dir/$name.expected" "$test_dir/$name.actual"; then
    printf 'welcome-spacing-test: %s output differs\nexpected: ' "$name" >&2
    od -An -tx1 "$test_dir/$name.expected" >&2
    printf 'actual:   ' >&2
    od -An -tx1 "$test_dir/$name.actual" >&2
    return 1
  fi
}

# The poem renderer's normal contract ends the title with one newline. The
# greeting adds exactly one more, leaving one empty row before the prompt.
run_case success 0 0 $'fetch\n' $'poem title\n'
assert_output success $'fetch\npoem title\n\n'

# A renderer can write a complete title and still return nonzero. This was the
# failure mode of the old `&& printf` chain: it conditionally lost the spacer.
run_case poem_failure 0 17 $'fetch\n' $'poem title\n'
assert_output poem_failure $'fetch\npoem title\n\n'

# Preserve the existing rule that the poem is skipped when fastfetch fails,
# while still terminating its output with a blank prompt boundary.
run_case fastfetch_failure 9 0 $'partial fetch\n' $'must not print\n'
assert_output fastfetch_failure $'partial fetch\n\n'

printf 'welcome spacing tests passed\n'
