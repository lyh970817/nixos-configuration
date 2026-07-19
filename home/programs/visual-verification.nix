{ config, pkgs, ... }:

let
  screenVerify = pkgs.callPackage ../../pkgs/screen-verify { };
  visualVerificationSkill = ../../skills/visual-verification;
in
{
  home.packages = [ screenVerify ];

  # The default Claude profile and Codex receive this skill via their
  # git-tracked skills/ dirs (dotfiles/{claude,codex}/skills/visual-verification
  # symlink into ../../skills), linked out-of-store in mutable-configs.nix.
  # Only the "mattpocock" Claude profile still needs an explicit store link.
  home.file.".config/claude-mattpocock/skills/visual-verification".source = visualVerificationSkill;
}
