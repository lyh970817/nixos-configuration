{ config, pkgs, ... }:

let
  screenVerify = pkgs.callPackage ../../pkgs/screen-verify { };
  # Repo-relative: the skill lives in this same config tree (skills/), so
  # reference it by relative path instead of a hardcoded checkout location.
  visualVerificationSkill = ../../skills/visual-verification;
in
{
  home.packages = [ screenVerify ];

  # Codex global skill.
  home.file.".codex/skills/visual-verification".source = visualVerificationSkill;

  # Same skill exposed to Claude Code in both the default and mattpocock profiles.
  home.file.".config/claude/skills/visual-verification".source = visualVerificationSkill;
  home.file.".config/claude-mattpocock/skills/visual-verification".source = visualVerificationSkill;
}
