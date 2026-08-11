{ ... }:

{
  environment.etc = {
    "codex/requirements.toml" = {
      mode = "0644";
      text = ''
        allow_managed_hooks_only = true

        [hooks]
        managed_dir = "/etc/codex/hooks"

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
  };
}
