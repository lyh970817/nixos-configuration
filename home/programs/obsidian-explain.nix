{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  vaultDir = "${config.home.homeDirectory}/Documents/explanations-vault";

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
  ];

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

      exec ${pkgs.obsidian}/bin/obsidian ${lib.escapeShellArg vaultUri} "$@"
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
    '';
  };
}
