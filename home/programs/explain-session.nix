{ pkgs, ... }:

let
  explainctl = pkgs.callPackage ../../pkgs/explainctl { };
  tylax = pkgs.callPackage ../../pkgs/tylax { };
in
{
  # Controller for forked Claude explanation workspaces (issue #11): forks the
  # origin Claude session into a dormant coordinator that maintains a
  # persistent Markdown tree under ~/.local/share/explanations. Invoked by the
  # explain-session skills, the Herdr trigger (scripts/herdr-explain-current),
  # and the Neovim explanation UI. Prompt templates and skill links are wired
  # in programs/mutable-configs.nix; the Kitty terminal it opens is installed
  # separately. tylax ships `t2l`, the Typst <-> LaTeX math converter
  # explainctl drives.
  home.packages = [
    explainctl
    tylax
  ];
}
