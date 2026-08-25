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
    pkgs.codex
  ];

  home.file.".codex-desktop/skills/nix-environment-setup".source =
    link "dotfiles/universal-skills/nix-environment-setup";

  home.file.".codex-desktop-orchestrator/skills/nix-environment-setup".source =
    link "dotfiles/universal-skills/nix-environment-setup";

  # Desktop may update config.toml at runtime, so seed an ordinary private file
  # rather than a read-only Home Manager symlink.
  home.activation.chatgptOrchestratorConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    orchestrator_home="$HOME/.codex-desktop-orchestrator"
    orchestrator_config="$orchestrator_home/config.toml"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$orchestrator_home"
    orchestrator_config_tmp="$(${pkgs.coreutils}/bin/mktemp "$orchestrator_config.XXXXXX")"
    run ${pkgs.coreutils}/bin/cp ${lib.escapeShellArg "${orchestratorConfig}"} "$orchestrator_config_tmp"
    run ${pkgs.coreutils}/bin/chmod 0600 "$orchestrator_config_tmp"
    run ${pkgs.coreutils}/bin/mv -f "$orchestrator_config_tmp" "$orchestrator_config"
  '';
}
