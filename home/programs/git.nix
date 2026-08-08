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
      # Repos that accumulate large ignored trees (this config's
      # .claude/worktrees/ holds ~19G of checkouts) make a cold `git status`
      # take ~650ms, which starship's git_status runs on every prompt — the
      # visible symptom is `cd` hanging. The untracked cache plus git 2.55's
      # Linux fsmonitor daemon bring warm status down to ~65ms.
      core.untrackedCache = true;
      core.fsmonitor = true;
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
