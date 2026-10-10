{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";
  orchestratorConfig = pkgs.writeText "chatgpt-orchestrator-config.toml" (
    builtins.readFile ../../dotfiles/codex/profiles/orchestrator.config.toml
  );
in

{
  home.packages = [
    pkgs.chatgpt
    # The phone client probes the host with read-only `command/exec` requests
    # whatever the profile's permissions are, and the app-server panics before
    # running them when no bwrap is on PATH. The app replaces the launcher's
    # PATH with the login shell's, so bwrap has to be in the user profile.
    pkgs.bubblewrap
  ];

  home.file.".codex-desktop/AGENTS.md".source = link "dotfiles/codex/desktop-AGENTS.md";

  home.file.".codex-desktop/skills/nix-environment-setup".source =
    link "dotfiles/universal-skills/nix-environment-setup";

  home.file.".codex-desktop-orchestrator/skills/nix-environment-setup".source =
    link "dotfiles/universal-skills/nix-environment-setup";

  # Keep the app's mutable settings while applying the managed defaults.
  home.activation.chatgptDesktopConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe pkgs.chatgpt.configureDesktop} "$HOME/.codex-desktop"
    run ${lib.getExe pkgs.chatgpt.configureDesktop} "$HOME/.codex-desktop-orchestrator" ${orchestratorConfig}
  '';
}
