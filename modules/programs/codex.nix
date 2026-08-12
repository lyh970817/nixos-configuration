{ ... }:

{
  environment.etc = {
    "codex/requirements.toml" = {
      mode = "0644";
      text = ''
        allow_managed_hooks_only = true

        [hooks]
        managed_dir = "/etc/codex/hooks"

        [[hooks.SessionStart]]

        [[hooks.SessionStart.hooks]]
        type = "command"
        command = "/etc/codex/hooks/herdr-title-hook.py"
        timeout = 1

        [[hooks.UserPromptSubmit]]

        [[hooks.UserPromptSubmit.hooks]]
        type = "command"
        command = "/etc/codex/hooks/herdr-title-hook.py"
        timeout = 1

        [[hooks.Stop]]

        [[hooks.Stop.hooks]]
        type = "command"
        command = "/etc/codex/hooks/response-simplifier.sh"
        timeout = 180
        statusMessage = "Rewriting the response in plain English"
      '';
    };

    "codex/hooks/response-simplifier.sh" = {
      source = ../../dotfiles/codex/hooks/response-simplifier.sh;
      mode = "0755";
    };

    "codex/hooks/herdr-title-hook.py" = {
      source = ../../scripts/herdr-title-hook.py;
      mode = "0755";
    };
  };
}
