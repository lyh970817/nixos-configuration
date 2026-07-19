{
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  settings = {
    security = {
      auth = {
        selectedType = "oauth-personal";
      };
    };
    general = {
      vimMode = true;
      previewFeatures = true;
    };
    ui = {
      showStatusInTitle = false;
    };
    tools = {
      autoAccept = true;
    };
    mcpServers = {
      context7 = {
        command = "npx";
        args = [
          "-y"
          "@upstash/context7-mcp@latest"
        ];
      };
    };
  };

in
{
  # Gemini coding CLI config: home role only. The gemini-cli package lives in
  # the home-only development package set, so its config is gated to match.
  config = lib.mkIf (osConfig.portable.role == "home") {
    home.file.".gemini/settings.json".text = builtins.toJSON settings;
    home.file.".gemini/GEMINI.md".text = "Always respond in English\n";

    # Ensure the directory exists for manual credential placement if needed
    # but do not manage secrets here.
  };
}
