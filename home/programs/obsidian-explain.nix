{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  vaultDir = "${config.home.homeDirectory}/Documents/explanations-vault";

  # Stable across generations, same rationale as explain-sync.nix: Obsidian's
  # environment is whatever launched it, so shell commands use the absolute
  # per-user profile path rather than trusting PATH.
  profileBin = "/etc/profiles/per-user/${config.home.username}/bin";

  # Everything below reproduces the validated pilot vault
  # (~/Documents/explain-pilot-vault, left untouched) declaratively. Plugin
  # payloads are fixed-output fetches of the exact GitHub release assets the
  # pilot ran -- verified byte-identical to the pilot's files -- so no plugin
  # binaries live in this repo.
  typstMate = version: asset: hash: {
    name = "plugins/typst-mate/${asset}";
    value = pkgs.fetchurl {
      url = "https://github.com/azyarashi/obsidian-typst-mate/releases/download/${version}/${asset}";
      inherit hash;
    };
  };
  shellCommands = version: asset: hash: {
    name = "plugins/obsidian-shellcommands/${asset}";
    value = pkgs.fetchurl {
      url = "https://github.com/Taitava/obsidian-shellcommands/releases/download/${version}/${asset}";
      inherit hash;
    };
  };
  inlineMath = version: asset: hash: {
    name = "plugins/inline-math/${asset}";
    value = pkgs.fetchurl {
      url = "https://github.com/RyotaUshio/obsidian-inline-math/releases/download/${version}/${asset}";
      inherit hash;
    };
  };

  # One Shell Commands entry, schema per newShellCommandConfiguration() in
  # plugin 0.23.0. Fixed ids (allowed alphabet [a-z0-9]): Obsidian addresses
  # the commands as obsidian-shellcommands:shell-command-<id> in hotkeys.json.
  shellCommand = id: alias: command: stdoutHandler: notifyStart: {
    inherit id alias;
    platform_specific_commands.default = command;
    shells = { };
    icon = null;
    confirm_execution = false;
    ignore_error_codes = [ ];
    input_contents.stdin = null;
    output_handlers = {
      stdout = {
        handler = stdoutHandler;
        convert_ansi_code = true;
      };
      stderr = {
        handler = "notification";
        convert_ansi_code = true;
      };
    };
    output_wrappers = {
      stdout = null;
      stderr = null;
    };
    output_channel_order = "stdout-first";
    output_handling_mode = "buffered";
    execution_notification_mode = if notifyStart then "quick" else null;
    events = { };
    debounce = null;
    command_palette_availability = "enabled";
    preactions = [ ];
    variable_default_values = { };
  };

  # Top-level plugin settings, schema per getDefaultSettings(true) in 0.23.0.
  # settings_version must match the installed release or the plugin refuses
  # the file; missing fields are filled with defaults on load.
  shellCommandsData = builtins.toJSON {
    settings_version = "0.23.0";
    shell_commands = [
      # {{file_path:absolute}} is the active note; submit shows start and
      # stdout/stderr notifications so the round-trip is visible in Obsidian.
      (shellCommand "explainsubmit" "Explain: submit"
        "${profileBin}/explain-sync submit {{file_path:absolute}}"
        "notification"
        true
      )
      # Palette-only; rsync is silent on success, so only signal start/errors.
      (shellCommand "explainpull" "Explain: pull" "${profileBin}/explain-sync pull" "ignore" true)
    ];
  };

  # Repo files are snapshotted through writeText so the activation script
  # carries a real store reference (see the rationale in mutable-configs.nix).
  seedFiles = builtins.listToAttrs [
    {
      name = "app.json";
      value = pkgs.writeText "obsidian-app.json" (
        builtins.toJSON {
          vimMode = true;
          livePreview = true;
        }
      );
    }
    {
      name = "community-plugins.json";
      value = pkgs.writeText "obsidian-community-plugins.json" (
        builtins.toJSON [
          "typst-mate"
          "obsidian-shellcommands"
          "inline-math"
        ]
      );
    }
    # Typst Mate 2.3.2 with the typst compiler wasm beside main.js, exactly
    # where the pilot placed it. Its defaults already render $...$/$$...$$
    # as Typst; data.json is the pilot's working settings
    # (openTypstToolsOnStartup: false included).
    (typstMate "2.3.2" "main.js" "sha256-B+Qg1W1K8Hit8dS7lqh1o6bj1g7uFstC92l02N63Z3c=")
    (typstMate "2.3.2" "manifest.json" "sha256-U2Hpt0lofqUrGiDv09qApwnWtOqUGAMcy8oAcD9+Kmo=")
    (typstMate "2.3.2" "styles.css" "sha256-u0LPSANUDFhiEtwlwgyROD5dkY8eCodg4Z5fmPJtCuc=")
    (typstMate "2.3.2" "typst-2.3.2.wasm" "sha256-MihFHj5kDS9amsQKOBbn84xWTHQUyElSU4rg5AJBUZ8=")
    {
      name = "plugins/typst-mate/data.json";
      value = pkgs.writeText "typst-mate-data.json" (
        builtins.readFile ./obsidian-explain/typst-mate-data.json
      );
    }
    (shellCommands "0.23.0" "main.js" "sha256-DF4kepHJbAr18+MzukO+QoVGlWbIGdWbfeEprTPRTYo=")
    (shellCommands "0.23.0" "manifest.json" "sha256-IK6Mz6iXICfTW0RX0htquGrryOOx3uXro02tGeRqJGI=")
    (shellCommands "0.23.0" "styles.css" "sha256-O9g4DlqlP8RH6mpMFN37lBmPGm0APm5fmUtFnPloTFM=")
    # inline-math ("No More Flickering Inline Math") ships no styles.css.
    (inlineMath "0.3.6" "main.js" "sha256-JI5Lda8Ftw3ZREZTfZJQQOxxzaS8rg0LTimaWdsFx+o=")
    (inlineMath "0.3.6" "manifest.json" "sha256-uvqxzVHNLlu1+6fQxyE90sr1YetJ2EEY5yJj05iL8zc=")
    {
      name = "plugins/inline-math/data.json";
      value = pkgs.writeText "inline-math-data.json" (
        builtins.toJSON {
          disableInTable = false;
          disableOnIME = true;
          disableDecorations = false;
          disableAtomicRanges = false;
        }
      );
    }
    # App hotkeys. Frees the chords Obsidian's defaults steal from
    # CodeMirror-vim (Ctrl+F search, Ctrl+B bold) and binds the explanation
    # workflow: Ctrl+Enter submit, Ctrl+Shift+Q insert question. Ctrl+Q would
    # be swallowed by the Electron menu's quit accelerator on Linux, hence the
    # Shift. Ctrl+U stays broken for vim: CodeMirror's built-in history keymap
    # binds Mod-u (undoSelection) below the hotkey layer, where no Obsidian
    # setting reaches — so Ctrl+D keeps its delete-paragraph default rather
    # than freeing only half of the half-page pair.
    {
      name = "hotkeys.json";
      value = pkgs.writeText "obsidian-hotkeys.json" (builtins.readFile ./obsidian-explain/hotkeys.json);
    }
    {
      name = "plugins/obsidian-shellcommands/data.json";
      value = pkgs.writeText "shellcommands-data.json" shellCommandsData;
    }
    # Core Templates plugin (enabled in Obsidian's defaults) serves the
    # question snippet; the folder is excluded from explain-sync push.
    {
      name = "templates.json";
      value = pkgs.writeText "obsidian-templates.json" (builtins.toJSON { folder = "_templates"; });
    }
  ];

  # Content seeded at the vault root rather than under .obsidian/.
  vaultFiles = {
    "_templates/question.md" = pkgs.writeText "obsidian-question-template.md" (
      builtins.readFile ./obsidian-explain/question-template.md
    );
  };

  # Opens the managed vault. The path form of the URI resolves only vaults
  # already listed in ~/.config/obsidian/obsidian.json — on an unregistered
  # path Obsidian shows a native error dialog (or silently does nothing)
  # rather than registering it, so the launcher writes the registry entry
  # itself first. A running instance receives the URI through Obsidian's
  # single-instance lock, otherwise this starts one.
  vaultUri = "obsidian://open?path=${lib.replaceStrings [ "/" ] [ "%2F" ] vaultDir}";
  obsidianExplain = pkgs.writeShellApplication {
    name = "obsidian-explain";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      vault=${lib.escapeShellArg vaultDir}
      registry="$HOME/.config/obsidian/obsidian.json"

      # Register the vault if the registry does not know it yet. Only ever add
      # a missing entry, atomically: a running Obsidian rewrites this file for
      # its own bookkeeping (ts, open) and tolerates a new entry appearing,
      # but not being clobbered.
      mkdir -p "''${registry%/*}"
      [ -s "$registry" ] || printf '{"vaults":{}}' > "$registry"
      if ! jq -e --arg path "$vault" \
          '.vaults // {} | any(.[]; .path == $path)' "$registry" >/dev/null; then
        id="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
        tmp="$(mktemp "$registry.XXXXXX")"
        jq --arg id "$id" --arg path "$vault" --argjson ts "$(date +%s%3N)" \
          '.vaults = ((.vaults // {}) + { ($id): { path: $path, ts: $ts } })' \
          "$registry" > "$tmp"
        mv "$tmp" "$registry"
      fi

      # Invoked over SSH (explain-dispatch-new) this inherits no session env;
      # rediscover it the way show-url does (html-open.nix), or Electron dies
      # on the missing XDG_RUNTIME_DIR. NIXOS_OZONE_WL makes the wrapper pick
      # the Wayland backend, as the desktop session does (hyprland.nix).
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        for sock in "$XDG_RUNTIME_DIR"/wayland-*; do
          case "$sock" in
            *.lock) continue ;;
          esac
          [ -S "$sock" ] || continue
          WAYLAND_DISPLAY="$(basename "$sock")"
          export WAYLAND_DISPLAY
          break
        done
      fi
      if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        echo "obsidian-explain: no Wayland socket under $XDG_RUNTIME_DIR" >&2
        exit 1
      fi
      export DISPLAY="''${DISPLAY:-:0}"
      export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-Hyprland}"
      export NIXOS_OZONE_WL=1

      # Detached, so an SSH caller returning does not take Obsidian with it;
      # a running instance picks the URI up and the child exits on its own.
      setsid -f ${pkgs.obsidian}/bin/obsidian ${lib.escapeShellArg vaultUri} "$@" \
        >/dev/null 2>&1 < /dev/null
    '';
  };
in
{
  # Obsidian-based viewer for explanation documents, laptop only. The vault is
  # seeded outside the repo; a separate sync wrapper fills it with content.
  config = lib.mkIf (osConfig.portable.role == "remote") {
    home.packages = [
      pkgs.obsidian
      obsidianExplain
    ];

    # Obsidian and its plugins rewrite every one of these files in place to
    # save settings, so none of them may be a read-only store symlink
    # (home.file would break saving). Seed once, then leave mutable: each file
    # is copied only if absent, writable by the owner.
    home.activation.obsidianExplainVault = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      obsidian_vault=${lib.escapeShellArg vaultDir}
      run ${pkgs.coreutils}/bin/install -d "$obsidian_vault"
      ${lib.concatStrings (
        lib.mapAttrsToList (rel: source: ''
          if [ ! -e "$obsidian_vault/.obsidian/"${lib.escapeShellArg rel} ]; then
            run ${pkgs.coreutils}/bin/install -D -m 0600 ${lib.escapeShellArg "${source}"} \
              "$obsidian_vault/.obsidian/"${lib.escapeShellArg rel}
          fi
        '') seedFiles
      )}
      ${lib.concatStrings (
        lib.mapAttrsToList (rel: source: ''
          if [ ! -e "$obsidian_vault/"${lib.escapeShellArg rel} ]; then
            run ${pkgs.coreutils}/bin/install -D -m 0600 ${lib.escapeShellArg "${source}"} \
              "$obsidian_vault/"${lib.escapeShellArg rel}
          fi
        '') vaultFiles
      )}
    '';
  };
}
