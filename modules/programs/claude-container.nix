{
  config,
  pkgs,
  lib,
  ...
}:

let
  claudeCodePackage = pkgs.claude-code;
  localeArchive = "${pkgs.glibcLocales}/lib/locale/locale-archive";
  ukLocale = "en_GB.UTF-8";
  ukEnvironment = {
    TZ = "Europe/London";
    LANG = ukLocale;
    LC_ALL = ukLocale;
    LANGUAGE = "en_GB:en";
    HTTP_PROXY = "http://127.0.0.1:7890";
    HTTPS_PROXY = "http://127.0.0.1:7890";
    ALL_PROXY = "socks5://127.0.0.1:7890";
    NO_PROXY = "localhost,127.0.0.1,::1,.local,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12";
    DISABLE_TELEMETRY = "1";
    DISABLE_ERROR_REPORTING = "1";
    ENABLE_EXPERIMENTAL_MCP_CLI = "true";
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    MCP_TIMEOUT = "60000";
  };
  localeCategories = [
    "LC_ADDRESS"
    "LC_IDENTIFICATION"
    "LC_MEASUREMENT"
    "LC_MONETARY"
    "LC_NAME"
    "LC_NUMERIC"
    "LC_PAPER"
    "LC_TELEPHONE"
    "LC_TIME"
  ];
  claudeContainerEntry = pkgs.writeShellApplication {
    name = "claude-container-entry";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.shadow
    ];
    text = ''
      if [ "$#" -lt 4 ]; then
        echo "usage: claude-container-entry <workdir> <term> <colorterm> <env-file> [claude args...]" >&2
        exit 64
      fi

      workdir="$1"
      term="$2"
      colorterm="$3"
      env_file="$4"
      shift 4

      if [ ! -d "$workdir" ]; then
        workdir="/home/andongni"
      fi

      forwarded_env=()
      if [ -r "$env_file" ]; then
        while IFS='=' read -r -d "" name value; do
          case "$name" in
            ANTHROPIC_AUTH_TOKEN|ANTHROPIC_BASE_URL|ANTHROPIC_DEFAULT_HAIKU_MODEL|ANTHROPIC_DEFAULT_OPUS_MODEL|ANTHROPIC_DEFAULT_SONNET_MODEL|CLAUDE_CODE_SUBAGENT_MODEL|CLAUDE_CONFIG_DIR|GITHUB_TOKEN|GH_TOKEN|GIT_ASKPASS|NIX_CONFIG|SSH_AUTH_SOCK|VISUAL|EDITOR)
              forwarded_env+=("$name=$value")
              ;;
          esac
        done < "$env_file"
      fi

      exec runuser -u andongni -- env \
        "''${forwarded_env[@]}" \
        HOME=/home/andongni \
        USER=andongni \
        LOGNAME=andongni \
        SHELL=/run/current-system/sw/bin/zsh \
        TERM="$term" \
        COLORTERM="$colorterm" \
        TZ="${ukEnvironment.TZ}" \
        LANG="${ukEnvironment.LANG}" \
        LC_ALL="${ukEnvironment.LC_ALL}" \
        LANGUAGE="${ukEnvironment.LANGUAGE}" \
        LOCALE_ARCHIVE="${localeArchive}" \
        HTTP_PROXY="${ukEnvironment.HTTP_PROXY}" \
        HTTPS_PROXY="${ukEnvironment.HTTPS_PROXY}" \
        ALL_PROXY="${ukEnvironment.ALL_PROXY}" \
        NO_PROXY="${ukEnvironment.NO_PROXY}" \
        http_proxy="${ukEnvironment.HTTP_PROXY}" \
        https_proxy="${ukEnvironment.HTTPS_PROXY}" \
        all_proxy="${ukEnvironment.ALL_PROXY}" \
        no_proxy="${ukEnvironment.NO_PROXY}" \
        DISABLE_TELEMETRY="${ukEnvironment.DISABLE_TELEMETRY}" \
        DISABLE_ERROR_REPORTING="${ukEnvironment.DISABLE_ERROR_REPORTING}" \
        ENABLE_EXPERIMENTAL_MCP_CLI="${ukEnvironment.ENABLE_EXPERIMENTAL_MCP_CLI}" \
        CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="${ukEnvironment.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS}" \
        MCP_TIMEOUT="${ukEnvironment.MCP_TIMEOUT}" \
        PATH=/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin \
        bash -lc "cd \"\$1\"; shift; exec claude \"\$@\"" -- "$workdir" "$@"
    '';
  };
in
{
  containers.claude-uk = {
    autoStart = false;
    ephemeral = true;
    privateNetwork = false;

    bindMounts."/home/andongni" = {
      hostPath = "/home/andongni";
      isReadOnly = false;
    };

    config =
      { pkgs, ... }:
      {
        networking.hostName = "claude-uk";

        nixpkgs.config.allowUnfree = true;

        time.timeZone = "Europe/London";

        i18n.defaultLocale = ukLocale;
        i18n.extraLocaleSettings = lib.genAttrs localeCategories (_: ukLocale);

        environment.variables = ukEnvironment;
        environment.sessionVariables = ukEnvironment;

        users.users.andongni = {
          isNormalUser = true;
          uid = 1000;
          group = "users";
          home = "/home/andongni";
          createHome = false;
          shell = pkgs.zsh;
        };

        programs.zsh.enable = true;

        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];

        environment.systemPackages = with pkgs; [
          bash
          bat
          cacert
          claudeContainerEntry
          claudeCodePackage
          coreutils
          curl
          fd
          file
          findutils
          git
          gnugrep
          gnumake
          gnused
          jq
          less
          lsd
          neovim
          nix
          nodejs_latest
          ripgrep
          shadow
          tree
          which
          zsh
        ];

        system.stateVersion = config.system.stateVersion;
      };
  };
}
