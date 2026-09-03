{
  config,
  pkgs,
  osConfig,
  ...
}:

let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";

  # Same host environment as the Claude launcher: pi and OMP have to reach
  # their providers through the local mihomo proxy, and their TUIs want a
  # stable locale/timezone.
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

      mode="''${THEME_MODE:-}"
      if [ -z "$mode" ]; then
        case "$(${pkgs.coreutils}/bin/readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
          *dark.lua) mode=dark ;;
          *light.lua) mode=light ;;
          *)
            echo "pi: cannot determine the terminal session theme" >&2
            exit 1
            ;;
        esac
      fi
      case "$mode" in
        dark) export COLORFGBG="15;0" ;;
        light) export COLORFGBG="0;15" ;;
        *)
          echo "pi: invalid THEME_MODE: $mode" >&2
          exit 1
          ;;
      esac

      exec ${pkgs.pi-coding-agent}/bin/pi "$@"
    '';
  };

  ompLauncher = pkgs.writeShellApplication {
    name = "omp";
    text = ''
      ${piHostEnvironment}

      exec ${pkgs.oh-my-pi}/bin/omp "$@"
    '';
  };
in
{
  # Pi uses its native `openai-codex` provider, independently of the
  # CLIProxyAPI gateway and OPENAI_API_KEY. Context compaction is offloaded to
  # the OpenAI server by the openai-server-compaction extension.
  #
  # One imperative bootstrap step remains: run `pi` once and use `/login` to
  # authorize the OAuth session. Pi keeps its own ~/.pi/agent/auth.json and
  # never reads ~/.codex/auth.json. See docs/pi-coding-agent.md, which also
  # explains why the 0.80.9 pin and the extension must be bumped together.
  home.packages = [
    ompLauncher
    piLauncher
  ];

  home.file = {
    # Both extensions are registered declaratively by absolute path in
    # settings.json's `packages` array. pi classifies a bare path as a local
    # package and only stats it, so no `pi install` and no network access are
    # involved.
    ".pi/agent/extensions/openai-server-compaction".source = pkgs.pi-openai-server-compaction;
    ".pi/agent/extensions/web-access".source = pkgs.pi-web-access;

    # The extension never writes this file, so a live out-of-store symlink is
    # safe. settings.json is materialized instead (pi rewrites it at runtime)
    # — see home/programs/mutable-configs.nix.
    ".pi/agent/openai-server-compaction.json".source = link "dotfiles/pi/openai-server-compaction.json";

    ".pi/agent/models.json".source = link "dotfiles/pi/models.json";
    ".pi/agent/skills/herdr".source = link "dotfiles/universal-skills/herdr";

    # pi never writes into its custom themes directory, so live symlinks are
    # safe here. The tracked settings select the pair as `eink/vt220-amber`;
    # Pi resolves it from the terminal background, with COLORFGBG supplied by
    # the wrapper as a process-local fallback when an OSC query cannot cross a
    # multiplexer.
    ".pi/agent/themes/eink.json".source = link "dotfiles/pi/themes/eink.json";
    ".pi/agent/themes/vt220-amber.json".source = link "dotfiles/pi/themes/vt220-amber.json";
  };
}
