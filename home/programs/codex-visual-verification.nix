{ config, pkgs, ... }:

let
  codexScreen = pkgs.callPackage ../../pkgs/codex-screen { };
  repository = "${config.home.homeDirectory}/Yandex.Disk/System/nixos-configuration";
  visualVerificationSkill = config.lib.file.mkOutOfStoreSymlink "${repository}/skills/visual-verification";
in
{
  home.packages = [ codexScreen ];

  # Codex global skill.
  home.file.".codex/skills/visual-verification".source = visualVerificationSkill;

  # Same skill exposed to Claude Code in both the default and mattpocock profiles.
  home.file.".config/claude/skills/visual-verification".source = visualVerificationSkill;
  home.file.".config/claude-mattpocock/skills/visual-verification".source = visualVerificationSkill;
}
