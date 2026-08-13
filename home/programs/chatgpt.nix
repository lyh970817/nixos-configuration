{ pkgs, ... }:

{
  home.packages = [
    pkgs.chatgpt
    pkgs.codex
  ];
}
