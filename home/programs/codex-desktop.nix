{
  pkgs,
  ...
}:

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
in
{
  # Keep terminal Apps disabled without changing the CLI Desktop launches.
  # The Desktop launcher also keeps GUI state out of ~/.codex.
  home.packages = [
    pkgs.codex
    firstmateCodexLauncher
  ];

  programs.codexDesktopLinux = {
    enable = true;
    package = pkgs.codex-desktop-isolated;
    # Desktop keeps Apps available in its own isolated Codex environment.
    cliPackage = pkgs.codex.override { disableApps = false; };
  };
}
