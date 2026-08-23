{ pkgs, ... }:

let
  tylax = pkgs.callPackage ../../pkgs/tylax { };
  explainctl = pkgs.callPackage ../../pkgs/explainctl { inherit tylax; };
in
{
  # Controller for forked Claude explanation workspaces (issue #11): forks the
  # origin Claude session into a dormant coordinator that maintains a
  # persistent Markdown tree under ~/.local/share/explanations. Invoked by the
  # explain-session skills, the Herdr trigger (scripts/herdr-explain-current),
  # and the Neovim explanation UI. Prompt templates and skill links are wired
  # in programs/mutable-configs.nix; the Kitty terminal it opens is installed
  # separately. tylax ships `t2l`: explainctl pipes agent LaTeX math through
  # it (l2t) to keep the trees canonically Typst, and the Neovim
  # `<localleader>t` keymap (dotfiles/nvim/lua/plugins/explain-typst.lua)
  # uses the other direction.
  home.packages = [
    explainctl
    tylax
  ];
}
