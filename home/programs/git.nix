{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "lyh970817";
    userEmail = "32429705+lyh970817@users.noreply.github.com";
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
