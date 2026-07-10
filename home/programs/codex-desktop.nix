{ pkgs, ... }:

let
  codexCli = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      user_codex="''${CODEX_USER_CLI_PATH:-$HOME/.npm-global/bin/codex}"
      if [ -x "$user_codex" ]; then
        exec "$user_codex" --profile desktop "$@"
      fi

      echo "Codex CLI not found at $user_codex" >&2
      exit 127
    '';
  };
in
{
  programs.codexDesktopLinux = {
    enable = true;
    cliPackage = codexCli;
  };
}
