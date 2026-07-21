{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    ignores = [
      "**/.claude/settings.local.json"
    ];
    settings = {
      user.name = "lyh970817";
      user.email = "32429705+lyh970817@users.noreply.github.com";
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
