# Print the shell greeting with one blank line before ZLE draws the prompt.
# Keep the separator independent of renderer status: a transient failure after
# either renderer has written output must not let the prompt consume that line.
print_shell_welcome() {
  # Panes created by Herdr launcher scripts (scripts/herdr-agent-launch,
  # scripts/herdr-explain-current) set HERDR_SCRIPTED_PANE=1: skip the whole
  # greeting (fastfetch and its helper forks, the poem) so the pane reaches a
  # stable prompt fast. Manually opened terminals keep the full greeting.
  [[ -n ${HERDR_SCRIPTED_PANE:-} ]] && return
  if fastfetch; then
    print_welcome_poem
  fi
  printf '\n'
}
