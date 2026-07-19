{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  codexCli = pkgs.writeShellApplication {
    name = "codex";
    text = ''
      user_codex="''${CODEX_USER_CLI_PATH:-$HOME/.npm-global/bin/codex}"
      if [ -x "$user_codex" ]; then
        exec "$user_codex" "$@"
      fi

      echo "Codex CLI not found at $user_codex" >&2
      exit 127
    '';
  };
in
{
  # Coding CLI / desktop integration: home role only. The remote laptop uses
  # Codex on the home box over `mosh home`.
  config = lib.mkIf (osConfig.portable.role == "home") {
    programs.codexDesktopLinux = {
      enable = true;
      cliPackage = codexCli;
    };
  };
}
