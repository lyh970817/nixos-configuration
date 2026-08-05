{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";
in

let
  # Alternate First Mate primary route, matching firstmateClaudeLauncher in
  # home/programs/claude.nix. fm-spawn.sh's codex crewmate launch template
  # always passes --dangerously-bypass-approvals-and-sandbox, so the primary
  # launcher matches it here to keep primary and crewmate YOLO behavior
  # identical, letting First Mate spawn crewmates without approval prompts
  # blocking either side.
  firstmateCodexLauncher = pkgs.writeShellApplication {
    name = "firstmate-codex";
    text = ''
      export FM_HOME="''${FM_HOME:-/home/andongni/firstmate}"
      cd "$FM_HOME"
      exec ${pkgs.codex}/bin/codex --dangerously-bypass-approvals-and-sandbox "$@"
    '';
  };

  # Same First Mate primary route, layered with the mattpocock skills profile
  # (~/.codex/mattpocock.config.toml, materialized from
  # dotfiles/codex/profiles/mattpocock.config.toml by the codexPolicy
  # activation script in mutable-configs.nix).
  firstmateCodexMattLauncher = pkgs.writeShellApplication {
    name = "firstmate-codex-matt";
    text = ''
      export FM_HOME="''${FM_HOME:-/home/andongni/firstmate}"
      cd "$FM_HOME"
      exec ${pkgs.codex}/bin/codex --profile mattpocock --dangerously-bypass-approvals-and-sandbox "$@"
    '';
  };
in
{
  # Keep terminal Apps disabled without changing the CLI Desktop launches.
  # The Desktop launcher also keeps GUI state out of ~/.codex.
  home.packages = [
    pkgs.codex
    firstmateCodexLauncher
    firstmateCodexMattLauncher
  ];

  home.file.".codex-desktop/skills/herdr".source = link "dotfiles/universal-skills/herdr";

  programs.codexDesktopLinux = {
    enable = true;
    package = pkgs.codex-desktop-isolated;
    # Desktop keeps Apps available in its own isolated Codex environment.
    cliPackage = pkgs.codex.override { disableApps = false; };
  };
}
