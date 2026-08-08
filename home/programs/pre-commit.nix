{
  lib,
  osConfig,
  preCommitCheck,
  ...
}:

let
  configDir = osConfig.portable.configDir;
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
    fi
  '';
}
