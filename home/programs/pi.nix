{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";

  # Same host environment as the Claude launcher: pi has to reach chatgpt.com
  # through the local mihomo proxy, and the TUI wants a stable locale/timezone.
  piHostEnvironment = ''
    export TZ="Europe/London"
    export TZDIR="${pkgs.tzdata}/share/zoneinfo"

    export LANG="en_GB.UTF-8"
    export LC_ALL="en_GB.UTF-8"
    export LANGUAGE="en_GB:en"
    export LOCALE_ARCHIVE="${pkgs.glibcLocales}/lib/locale/locale-archive"

    export HTTP_PROXY="''${HTTP_PROXY:-http://127.0.0.1:7890}"
    export HTTPS_PROXY="''${HTTPS_PROXY:-http://127.0.0.1:7890}"
    export ALL_PROXY="''${ALL_PROXY:-socks5h://127.0.0.1:7890}"
    export NO_PROXY="''${NO_PROXY:-localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12}"

    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    export all_proxy="$ALL_PROXY"
    export no_proxy="$NO_PROXY"
  '';

  piLauncher = pkgs.writeShellApplication {
    name = "pi";
    text = ''
      ${piHostEnvironment}

      exec ${pkgs.pi-coding-agent}/bin/pi "$@"
    '';
  };
in
{
  # pi coding agent, driven by GPT models from the ChatGPT/Codex subscription
  # through pi's own native `openai-codex` provider — not the CLIProxyAPI
  # gateway and not an OPENAI_API_KEY. Context compaction is offloaded to the
  # OpenAI server by the openai-server-compaction extension.
  #
  # One imperative bootstrap step remains: run `pi` once and use `/login` to
  # authorize the OAuth session. pi keeps its own ~/.pi/agent/auth.json and
  # never reads ~/.codex/auth.json. See docs/pi-coding-agent.md, which also
  # explains why the 0.80.9 pin and the extension must be bumped together.
  home.packages = [ piLauncher ];

  home.file = {
    # Registered declaratively by absolute path in settings.json's `packages`
    # array. pi classifies a bare path as a local package and only stats it,
    # so no `pi install` and no network access are involved.
    ".pi/agent/extensions/openai-server-compaction".source = pkgs.pi-openai-server-compaction;

    # The extension never writes this file, so a live out-of-store symlink is
    # safe. settings.json is materialized instead (pi rewrites it at runtime)
    # — see home/programs/mutable-configs.nix.
    ".pi/agent/openai-server-compaction.json".source = link "dotfiles/pi/openai-server-compaction.json";

    # pi never writes into its custom themes directory, so a live symlink is
    # safe here too. Colors are ANSI palette indices (0-15), not hex, so this
    # theme tracks whatever dark.toml in home/programs/alacritty.nix defines.
    ".pi/agent/themes/matrix.json".source = link "dotfiles/pi/themes/matrix.json";
  };
}
