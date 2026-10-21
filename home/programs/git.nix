{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Yandex.Disk uploads the .git of newly synced directories even though its
  # config excludes .git, so a repo created or cloned under ~/Yandex.Disk must
  # keep its git dir outside the synced tree. This wrapper shadows git on PATH
  # (lib.hiPrio wins the bin/git collision with programs.git's package) and,
  # only for `git init` / `git clone` whose target resolves under
  # ~/Yandex.Disk, adds --separate-git-dir=~/.local/share/git-dirs/<rel>.git so
  # the Disk holds just a `.git` pointer file. Every other invocation, and any
  # init/clone it cannot parse with certainty, is exec'd to the real git
  # untouched. git's own internal sub-invocations use its exec-path, not PATH.
  # No runtimeInputs: those would prepend to PATH for git's children (hooks).
  realGit = "${pkgs.git}/bin/git";
  gitDiskWrapper = pkgs.writeShellApplication {
    name = "git";
    text = ''
      real_git=${realGit}

      # Fast path: find the subcommand, skipping global options.
      cwd_steps=()
      i=1
      sub=""
      while [ "$i" -le "$#" ]; do
        a="''${!i}"
        case "$a" in
          -C)
            i=$((i + 1))
            [ "$i" -le "$#" ] || exec "$real_git" "$@"
            cwd_steps+=("''${!i}")
            ;;
          -c | --config-env | --namespace | --attr-source)
            i=$((i + 1))
            ;;
          --git-dir | --git-dir=* | --work-tree | --work-tree=* | --bare)
            exec "$real_git" "$@"
            ;;
          -*) ;;
          *)
            sub="$a"
            break
            ;;
        esac
        i=$((i + 1))
      done
      case "$sub" in
        init | clone) ;;
        *) exec "$real_git" "$@" ;;
      esac
      if [ -n "''${GIT_DIR:-}" ] || [ -n "''${GIT_WORK_TREE:-}" ]; then
        exec "$real_git" "$@"
      fi

      realpath=${pkgs.coreutils}/bin/realpath
      base="$PWD"
      for step in "''${cwd_steps[@]}"; do
        [ -n "$step" ] || continue
        case "$step" in
          /*) base="$step" ;;
          *) base="$base/$step" ;;
        esac
      done

      # Parse the subcommand's own options; anything unknown -> plain git.
      pos=()
      j=$((i + 1))
      dashdash=0
      while [ "$j" -le "$#" ]; do
        a="''${!j}"
        if [ "$dashdash" -eq 1 ]; then
          pos+=("$a")
          j=$((j + 1))
          continue
        fi
        case "$sub:$a" in
          *:--) dashdash=1 ;;
          *:--separate-git-dir | *:--separate-git-dir=* | *:--bare | clone:--mirror)
            exec "$real_git" "$@"
            ;;
          *:--template | *:--initial-branch | init:-b | clone:-b | clone:--branch             | clone:-o | clone:--origin | clone:-u | clone:--upload-pack             | clone:--reference | clone:--reference-if-able | clone:--depth             | clone:--shallow-since | clone:--shallow-exclude | clone:-c             | clone:--config | clone:-j | clone:--jobs | clone:--server-option             | clone:--filter | clone:--bundle-uri | clone:--revision             | *:--object-format | *:--ref-format)
            j=$((j + 1))
            [ "$j" -le "$#" ] || exec "$real_git" "$@"
            ;;
          *:--template=* | init:--initial-branch=* | init:-b?* | *:--object-format=*             | *:--ref-format=* | *:-q | *:--quiet | init:--shared | init:--shared=*) ;;
          clone:--branch=* | clone:-b?* | clone:--origin=* | clone:-o?*             | clone:--upload-pack=* | clone:-u?* | clone:--reference=*             | clone:--reference-if-able=* | clone:--depth=* | clone:--shallow-since=*             | clone:--shallow-exclude=* | clone:--config=* | clone:-c?*             | clone:--jobs=* | clone:-j?* | clone:--server-option=* | clone:--filter=*             | clone:--bundle-uri=* | clone:--revision=* | clone:--recurse-submodules             | clone:--recurse-submodules=* | clone:--recursive | clone:--recursive=*             | clone:-l | clone:--local | clone:--no-local | clone:--no-hardlinks             | clone:-s | clone:--shared | clone:-v | clone:--verbose | clone:-n             | clone:--no-checkout | clone:--progress | clone:--no-progress             | clone:--tags | clone:--no-tags             | clone:--single-branch | clone:--no-single-branch             | clone:--shallow-submodules | clone:--no-shallow-submodules             | clone:--remote-submodules | clone:--no-remote-submodules             | clone:--sparse | clone:--reject-shallow | clone:--no-reject-shallow             | clone:--dissociate | clone:--also-filter-submodules) ;;
          *:-*) exec "$real_git" "$@" ;;
          *) pos+=("$a") ;;
        esac
        j=$((j + 1))
      done

      if [ "$sub" = init ]; then
        [ "''${#pos[@]}" -le 1 ] || exec "$real_git" "$@"
        target="''${pos[0]:-.}"
      else
        case "''${#pos[@]}" in
          2) target="''${pos[1]}" ;;
          1)
            # git's guess_dir_name: drop trailing slashes, a trailing /.git,
            # then a .git or .bundle suffix; keep what follows the last / or :.
            url="''${pos[0]}"
            while [ "''${url%/}" != "$url" ]; do url="''${url%/}"; done
            url="''${url%/.git}"
            while [ "''${url%/}" != "$url" ]; do url="''${url%/}"; done
            name="''${url##*[/:]}"
            name="''${name%.git}"
            name="''${name%.bundle}"
            case "$name" in
              "" | . | .. | *[[:space:]]* | *@*) exec "$real_git" "$@" ;;
            esac
            # A bare host URL (scheme://host[:port]) has no path to name it by.
            case "$url" in
              *://*/*) ;;
              *://*) exec "$real_git" "$@" ;;
            esac
            target="$name"
            ;;
          *) exec "$real_git" "$@" ;;
        esac
      fi

      case "$target" in
        /*) ;;
        *) target="$base/$target" ;;
      esac
      target="$("$realpath" -m -- "$target")" || exec "$real_git" "$@"
      disk="$("$realpath" -m -- "$HOME/Yandex.Disk")"
      case "$target" in
        "$disk"/*) ;;
        *) exec "$real_git" "$@" ;;
      esac
      # Re-initialising an existing repo with --separate-git-dir would move
      # its git dir; leave that to an explicit command.
      [ ! -e "$target/.git" ] || exec "$real_git" "$@"

      rel="''${target#"$disk"/}"
      store="$HOME/.local/share/git-dirs"
      gitdir="$store/$rel.git"
      if [ -e "$gitdir" ]; then
        echo "git: $gitdir already exists; remove it or pass --separate-git-dir explicitly" >&2
        exit 128
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$store"
      ${pkgs.coreutils}/bin/chmod 700 "$store"
      ${pkgs.coreutils}/bin/mkdir -p "''${gitdir%/*}"
      echo "git: Yandex.Disk target; git dir -> $gitdir" >&2

      # Insert the flag right after the subcommand.
      args=("$@")
      exec "$real_git" "''${args[@]:0:i}" "--separate-git-dir=$gitdir" "''${args[@]:i}"
    '';
  };
in
{
  home.packages = [ (lib.hiPrio gitDiskWrapper) ];

  programs.git = {
    enable = true;
    ignores = [
      "**/.claude/settings.local.json"
    ];
    settings = {
      user.name = "lyh970817";
      user.email = "32429705+lyh970817@users.noreply.github.com";
      safe.directory = "*";
      # Repos that accumulate large ignored trees (this config's
      # .claude/worktrees/ holds ~19G of checkouts) make a cold `git status`
      # take ~650ms, which starship's git_status runs on every prompt — the
      # visible symptom is `cd` hanging. The untracked cache plus git 2.55's
      # Linux fsmonitor daemon bring warm status down to ~65ms.
      core.untrackedCache = true;
      core.fsmonitor = true;
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      aliases = {
        co = "pr checkout";
      };
    };
  };
}
