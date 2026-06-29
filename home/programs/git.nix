{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    ignores = [
      "**/.claude/settings.local.json"
    ];
    settings = {
      safe.directory = "*";
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      aliases = {
        co = "pr checkout";
      };
    };
  };
}
