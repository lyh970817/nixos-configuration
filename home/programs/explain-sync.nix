{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

# Laptop-side editing for the explanation workflow. The trees stay canonical
# on linglong (~/.local/share/explanations, where explainctl and the agents
# run); the laptop edits a mirror in an Obsidian vault at
# ~/Documents/explanations-vault. Sync is deliberately rough: explicit
# push/submit/pull wrappers, no continuous sync — explainctl's staging-hash
# conflict protocol catches the race where a push lands mid-update.
#
# `explain-sync` (remote role) runs on the laptop; `explain-dispatch-new`
# (home role) runs on linglong, called by the Neovim explain module after
# `explainctl new` so a remote viewer gets the fresh tree in the vault
# without touching the local nvim-tab flow. `explain-remote-new` (home role)
# is the F7 remote path (scripts/herdr-explain-current): it creates a
# pending stub tree and dispatches it, so the question is typed straight
# into Obsidian and the first submit runs the bootstrap.

let
  peerHost = osConfig.portable.peerHost;

  explainctl = pkgs.callPackage ../../pkgs/explainctl { };

  # Stable across generations; see html-open.nix for why SSH dispatch needs a
  # fixed absolute location for peer-side helpers. Same username on both
  # machines, so one path serves both directions.
  profileBin = "/etc/profiles/per-user/${config.home.username}/bin";

  viewerIsRemote = pkgs.callPackage ../../pkgs/viewer-is-remote.nix { };

  vaultDir = "Documents/explanations-vault";
  storeDir = ".local/share/explanations";

  # Never sync explainctl's runtime state: the lock and the staging/failed
  # directories stay on linglong.
  pullExcludes = "--exclude '.explain.lock' --exclude '.staging*' --exclude '.submit-*' --exclude '.failed-*'";

  explainSync = pkgs.writeShellApplication {
    name = "explain-sync";
    runtimeInputs = [
      pkgs.rsync
      pkgs.openssh
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}
      VAULT="$HOME/${vaultDir}"
      STORE=${pkgs.lib.escapeShellArg storeDir}

      usage() {
        echo "explain-sync: usage: explain-sync pull [tree] | push [tree] | submit FILE" >&2
        exit 2
      }

      [ -n "$PEER" ] || { echo "explain-sync: no peer host configured" >&2; exit 1; }
      mkdir -p "$VAULT"

      # accept-new rather than a pinned key: the peer's identity is enforced
      # by the tailnet (see html-open.nix).
      SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)

      # linglong -> vault: everything except explainctl runtime state, and
      # never --delete: an unsaved local edit must survive a pull.
      pull() {
        local tree="''${1:-}"
        rsync -a -e "ssh ''${SSH_OPTS[*]}" \
          ${pullExcludes} \
          "$PEER:$STORE/$tree''${tree:+/}" "$VAULT/$tree''${tree:+/}"
      }

      # vault -> linglong: only Markdown, the single thing the human edits.
      # Hidden entries (vault config, .explain.json, .context.md) never
      # travel this way, and nothing is ever deleted on the peer.
      # _templates holds Obsidian template snippets (obsidian-explain.nix),
      # vault furniture that must not land in the canonical store on a
      # whole-vault push.
      push() {
        local tree="''${1:-}"
        rsync -am -e "ssh ''${SSH_OPTS[*]}" \
          --exclude '.*' --exclude '_templates' \
          --include '*/' --include '*.md' --exclude '*' \
          "$VAULT/$tree''${tree:+/}" "$PEER:$STORE/$tree''${tree:+/}"
      }

      # Map a remote tree path (absolute, under .../explanations/) to its
      # vault twin.
      to_local() {
        printf '%s/%s\n' "$VAULT" "''${1#*/explanations/}"
      }

      open_locally() {
        # Loose coupling to the Obsidian side: use its launcher when
        # installed, otherwise just say where the document is.
        if command -v obsidian-explain >/dev/null 2>&1; then
          obsidian-explain "$1" || true
        else
          echo "explain-sync: open: $1"
        fi
      }

      submit() {
        local file rel tree json code status
        file="$(realpath "$1")"
        case "$file" in
          "$VAULT"/*/*) ;;
          *)
            echo "explain-sync: $file is not inside a tree in $VAULT" >&2
            exit 1
            ;;
        esac
        rel="''${file#"$VAULT"/}"
        tree="''${rel%%/*}"

        push "$tree"

        # The remote path is relative to the peer's home, where the SSH
        # command lands; printf %q survives the remote shell's word split.
        # Client-side expansion is the point here, hence the %q quoting.
        code=0
        # shellcheck disable=SC2029
        json=$(ssh "''${SSH_OPTS[@]}" "$PEER" \
          "$(printf '%q ' ${profileBin}/explainctl submit --json "$STORE/$rel")") \
          || code=$?
        status=$(jq -r '.status // empty' <<<"$json" 2>/dev/null || true)

        case "$status" in
          updated)
            pull "$tree"
            echo "explain-sync: explanation updated"
            jq -r '.resolved_question_ids[]? | "explain-sync: resolved \(.)"' <<<"$json"
            # Focus the submitted note itself: a bootstrap classifies the
            # root as updated, not created, so without this a bootstrap that
            # creates no children would finish with nothing brought forward.
            # Re-opening an already-open note is a harmless focus.
            open_locally "$file"
            local created
            while IFS= read -r created; do
              [ -n "$created" ] || continue
              open_locally "$(to_local "$created")"
            done < <(jq -r '.created[]?' <<<"$json")
            ;;
          no_questions)
            echo "explain-sync: no open questions; nothing submitted"
            ;;
          conflict)
            # The live tree changed while the update ran; nothing was
            # committed. Pull the current state and point at the staged
            # result kept on linglong.
            pull "$tree"
            echo "explain-sync: conflict — tree changed during the update" >&2
            echo "explain-sync: staged result on $PEER: $(jq -r '.staged // empty' <<<"$json")" >&2
            exit 1
            ;;
          busy)
            echo "explain-sync: an update is already running on $PEER" >&2
            exit 75
            ;;
          *)
            echo "explain-sync: submit failed (exit $code)" >&2
            [ -z "$json" ] || printf '%s\n' "$json" >&2
            exit 1
            ;;
        esac
      }

      case "''${1:-}" in
        pull) pull "''${2:-}" ;;
        push) push "''${2:-}" ;;
        submit)
          [ -n "''${2:-}" ] || usage
          submit "$2"
          ;;
        *) usage ;;
      esac
    '';
  };

  explainDispatchNew = pkgs.writeShellApplication {
    name = "explain-dispatch-new";
    runtimeInputs = [
      pkgs.rsync
      pkgs.openssh
      pkgs.jq
      pkgs.coreutils
      viewerIsRemote
    ];
    text = ''
      PEER=${pkgs.lib.escapeShellArg peerHost}
      VAULT=${pkgs.lib.escapeShellArg vaultDir}

      if [ -z "''${1:-}" ]; then
        echo "explain-dispatch-new: usage: explain-dispatch-new TREE_ROOT" >&2
        exit 2
      fi
      root="$(realpath "$1")"
      if [ ! -f "$root/.explain.json" ]; then
        echo "explain-dispatch-new: $root is not an explanation root" >&2
        exit 2
      fi

      # A local viewer already has the nvim tab; nothing to dispatch.
      if [ -z "$PEER" ] || ! viewer-is-remote; then
        exit 0
      fi

      slug="$(basename "$root")"
      rsync -a -e "ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new" \
        ${pullExcludes} \
        "$root/" "$PEER:$VAULT/$slug/"

      focus="$(jq -r '.root_document // "explanation.md"' "$root/.explain.json")"
      # A bare SSH command carries no Wayland session env; like show-url
      # (html-open.nix), obsidian-explain rediscovers it on the peer and
      # detaches, so this plain invocation is enough. Loose coupling: the
      # launcher may not be installed on the peer yet; the sync above already
      # delivered the document, so failure here only prints where it is.
      if ! ssh -o BatchMode=yes -o ConnectTimeout=10 \
          -o StrictHostKeyChecking=accept-new "$PEER" \
          "$(printf '%q ' ${profileBin}/obsidian-explain "$VAULT/$slug/$focus")"; then
        echo "explain-dispatch-new: synced to $PEER:$VAULT/$slug; could not open Obsidian" >&2
      fi
    '';
  };
  explainRemoteNew = pkgs.writeShellApplication {
    name = "explain-remote-new";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
      viewerIsRemote
      explainctl
    ];
    text = ''
      # F7 remote path (scripts/herdr-explain-current): when the human views
      # this machine from the laptop, no nvim tab is opened at all. Create a
      # pending stub tree (fast, no Claude run) and hand it to
      # explain-dispatch-new, which rsyncs it into the laptop vault and opens
      # it in Obsidian. The user types the question into the opened note; its
      # first submit (explain-sync submit on the laptop) runs the bootstrap
      # against the origin binding recorded here.
      #
      # Exit codes: 0 = a fresh stub is open on the laptop; 3 = viewer is
      # local (the caller keeps the nvim tab flow); 4 = an existing pending
      # stub for this session was reopened rather than duplicated; else
      # failure, detail on stderr.
      PEER=${pkgs.lib.escapeShellArg peerHost}

      usage() {
        echo "explain-remote-new: usage: --session-id ID --cwd DIR --launcher NAME" >&2
        exit 2
      }
      session_id="" origin_cwd="" launcher=""
      while [ $# -gt 0 ]; do
        case "$1" in
          --session-id) session_id=''${2:-} ;;
          --cwd) origin_cwd=''${2:-} ;;
          --launcher) launcher=''${2:-} ;;
          *) usage ;;
        esac
        shift 2 || usage
      done
      { [ -n "$session_id" ] && [ -n "$origin_cwd" ] && [ -n "$launcher" ]; } || usage

      if [ -z "$PEER" ] || ! viewer-is-remote; then
        exit 3
      fi

      if ! out=$(explainctl new --pending --session-id "$session_id" \
        --cwd "$origin_cwd" --launcher "$launcher" --no-open); then
        echo "explain-remote-new: explainctl new --pending failed" >&2
        exit 1
      fi
      root=$(jq -r '.root // empty' <<<"$out")
      if [ -z "$root" ]; then
        echo "explain-remote-new: explainctl reported no tree root" >&2
        exit 1
      fi
      # `existing` means a pending stub for this origin session was already
      # waiting and was handed back instead of a new one being minted.
      # Reporting that distinctly is the whole point: otherwise a repeat F7
      # re-dispatches the same note and looks like nothing happened.
      status=$(jq -r '.status // empty' <<<"$out")

      # The dispatch is what makes the note appear on the laptop; its
      # failure fails the flow (the caller notifies). The stub stays behind
      # either way and the message names it.
      if ! ${explainDispatchNew}/bin/explain-dispatch-new "$root"; then
        echo "explain-remote-new: created $root but could not open it on the laptop" >&2
        exit 1
      fi
      if [ "$status" = existing ]; then
        echo "explain-remote-new: reopened the pending stub $root on $PEER"
        exit 4
      fi
      echo "explain-remote-new: $root open on $PEER"
    '';
  };
in
{
  home.packages =
    lib.optionals (osConfig.portable.role == "remote") [ explainSync ]
    ++ lib.optionals (osConfig.portable.role == "home") [
      explainDispatchNew
      explainRemoteNew
    ];
}
