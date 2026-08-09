{
  lib,
  pkgs,
  osConfig,
  preCommitCheck,
  ...
}:

let
  configDir = osConfig.portable.configDir;

  # pre-commit's installer bakes a *repo-relative* config path into the hook it
  # writes, and that path only resolves in the main checkout. A linked worktree
  # (`.claude/worktrees/*`) has no `.pre-commit-config.yaml` of its own, so every
  # commit made there aborted with "No .pre-commit-config.yaml file was found"
  # and the whole screen was skipped -- exactly the checks a rebuild cannot
  # replace. Own the hook instead and give it an absolute config path. Neither
  # the hook nor the config lives in a working tree, so one installation covers
  # the main checkout and every worktree, including ones added later by hand.
  gitHooks = pkgs.writeTextFile {
    name = "pre-commit-git-hooks";
    destination = "/pre-commit";
    executable = true;
    text = ''
      #!${pkgs.runtimeShell}
      exec ${pkgs.pre-commit}/bin/pre-commit hook-impl \
        --config=${configDir}/.pre-commit-config.yaml \
        --hook-type=pre-commit \
        --hook-dir "''${0%/*}" -- "$@"
    '';
  };
in
{
  # pre-commit-hooks.nix generates the hooks, but ships their installer only as
  # the devShell's shellHook. This repo is edited and committed in place, never
  # through `nix develop`, so on a fresh clone that hook never ran and .git/hooks
  # stayed empty -- the documented commit gate silently did not exist. Run the
  # same installer at activation instead, so both machines pick the hooks up
  # from a rebuild with no setup step to remember.
  #
  # The installer is convergent: it compares the .pre-commit-config.yaml symlink
  # against the store path it would write and returns immediately when they
  # already match, so the steady-state cost here is one readlink.
  home.activation.installPreCommitHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d ${lib.escapeShellArg configDir}/.git ]; then
      (
        # The installer leans on `[ -L f ] && unlink f` and similar, which trip
        # activation's errexit even on the ordinary not-a-symlink path.
        set +eu
        # It registers the generated config as a GC root through a bare
        # `nix-store`, which activation's PATH does not carry.
        PATH="/run/current-system/sw/bin:$PATH"
        cd ${lib.escapeShellArg configDir} && ${preCommitCheck.shellHook}
      ) || true

      # The installer clears core.hooksPath and repoints it at .git/hooks
      # whenever it regenerates the config, so claim it back on every
      # activation. Its own hook stays there unused; git runs only this one.
      ${pkgs.git}/bin/git -C ${lib.escapeShellArg configDir} \
        config --local core.hooksPath ${gitHooks} || true
    fi
  '';
}
