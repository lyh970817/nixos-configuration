{
  pkgs,
  lib,
  osConfig,
  ...
}:

{
  # Coding CLI: pkgs.codex on both roles. Desktop tray integration stays
  # home role only, pointed at the same package (cliPackage only feeds the
  # tray's CODEX_CLI_PATH wrapper, not PATH, so this doesn't double-install).
  config = {
    home.packages = [ pkgs.codex ];
  }
  // lib.optionalAttrs (osConfig.portable.role == "remote") {
    # config.toml is machine-local and intentionally unmanaged. Older shared
    # configs can retain a node_repl command pointing into the home-only
    # Codex Desktop derivation. Remove just that legacy entry on activation:
    # the remote has no Desktop/browser backend to supply its executable.
    home.activation.removeStaleCodexDesktopNodeRepl = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if ${pkgs.codex}/bin/codex mcp get node_repl 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -Eq '^  command: /nix/store/.*-codex-desktop-.*/opt/codex-desktop/resources/node_repl$'; then
        ${pkgs.codex}/bin/codex mcp remove node_repl
      fi
    '';
  }
  // lib.optionalAttrs (osConfig.portable.role == "home") {
    programs.codexDesktopLinux = {
      enable = true;
      cliPackage = pkgs.codex;
    };
  };
}
