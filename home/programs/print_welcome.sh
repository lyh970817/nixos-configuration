# Print the shell greeting with one blank line before ZLE draws the prompt.
# Keep the separator independent of renderer status: a transient failure after
# either renderer has written output must not let the prompt consume that line.
print_shell_welcome() {
  if fastfetch; then
    print_welcome_poem
  fi
  printf '\n'
}
