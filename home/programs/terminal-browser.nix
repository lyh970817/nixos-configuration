{
  config,
  lib,
  pkgs,
  ...
}:

let
  skills = "${pkgs.terminal-browser}/lib/terminal-browser/skills";
in
{
  home.packages = [ pkgs.terminal-browser ];

  # Home Manager owns the agent skill links. Without the declined choice the
  # CLI relinks them itself on every version change, replacing these links
  # with its own and writing into ~/.claude and ~/.agents as well.
  home.file = {
    ".config/claude/skills/terminal-browser".source = "${skills}/default/terminal-browser";
    ".codex/skills/terminal-browser".source = "${skills}/codex/terminal-browser";
  };

  # A plain file, not a store link: `terminal-browser setup` rewrites it.
  home.activation.terminalBrowserSkillChoice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.xdg.stateHome}/terminal-browser"
    run ${pkgs.bash}/bin/bash -c 'echo no > "$1"' _ "${config.xdg.stateHome}/terminal-browser/skills-choice"
  '';
}
