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

  # First Mate is a project-local distribution. OMP does not discover tracked
  # `.pi/extensions`, so the primary launcher must load both the turn-end guard
  # and the OMP-native watcher explicitly. The PI markers remain the primary
  # harness contract; FM_OMP_HARNESS is a separate process-scoped discriminator.
  # The OMP crewmate adapter overrides FM_OMP_PRIMARY to 0.
  firstmateLauncher = pkgs.writeShellApplication {
    name = "firstmate";
    text = ''
      ${piHostEnvironment}

      export FM_HOME="/home/andongni/firstmate"
      export PI_CODING_AGENT=true
      export FM_PI_HARNESS=pi
      export FM_OMP_HARNESS=omp
      export FM_OMP_PRIMARY=1
      cd "$FM_HOME"
      exec ${ompLauncher}/bin/omp \
        -e "$FM_HOME/.pi/extensions/fm-primary-turnend-guard.ts" \
        -e "$FM_HOME/.pi/extensions/fm-primary-omp-watch.ts" \
        "$@"
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
    firstmateLauncher

    # First Mate's bootstrap remains detection-only. Nix owns these pinned
    # executables, while optional AXI hook integrations remain disabled: do not
    # run their imperative `setup hooks` commands.
    pkgs.treehouse
    pkgs."no-mistakes"
    pkgs.gh-axi
    pkgs.chrome-devtools-axi
    pkgs.lavish-axi
    pkgs.tasks-axi
    pkgs.quota-axi
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

    # pi never writes into its custom themes directory, so a live symlink is
    # safe here too. Colors are ANSI palette indices (0-15), not hex, so this
    # theme tracks whatever dark.toml in home/programs/alacritty.nix defines.
    ".pi/agent/themes/matrix.json".source = link "dotfiles/pi/themes/matrix.json";
  };
}
