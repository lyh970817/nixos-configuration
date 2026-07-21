{
  pkgs,
  ...
}:

{
  # Codex Desktop owns the bundled node_repl MCP and provides the matching
  # Codex CLI wrapper, so both stay available on every portable role.
  programs.codexDesktopLinux = {
    enable = true;
    cliPackage = pkgs.codex;
  };
}
