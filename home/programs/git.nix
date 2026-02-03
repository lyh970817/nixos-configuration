{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    ignores = [
      "**/.claude/settings.local.json"
    ];
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
