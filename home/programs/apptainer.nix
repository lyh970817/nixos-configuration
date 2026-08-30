{
  config,
  lib,
  osConfig,
  ...
}:

# Persistent container image cache.
#
# Nextflow defaults its Singularity cache to `<workdir>/singularity/`, so every
# pipeline run under a throwaway work directory re-pulls and re-stores the same
# images: one finished scratch tree held eleven byte-identical copies of the
# same 156 MiB blob and eleven of another at 81 MiB. A fixed cache location
# makes that one copy shared by every run, and puts it outside /tmp so scratch
# aging (modules/system/tmp-aging.nix) cannot destroy it.
#
# `~/.apptainer` is the location because modules/services/restic-backup.nix
# already excludes that whole directory as re-pullable container images, so the
# Nextflow cache inherits the exclusion instead of needing a second rule and
# pushing gigabytes of registry-fetchable data into the Yandex repository. It
# is also where apptainer's own OCI blob cache already lives, which keeps every
# container byte on the machine under one path that one `du` can answer for.
#
# Deliberately not `~/.cache`: that tree is treated as freely disposable and is
# the first thing cleared under disk pressure, which is exactly the fate these
# images have to be protected from.
#
# Only the home role, matching where nextflow and apptainer are installed
# (home/packages/development.nix).

let
  cacheRoot = "${config.home.homeDirectory}/.apptainer";
in

{
  config = lib.mkIf (osConfig.portable.role == "home") {
    home.sessionVariables = {
      # Apptainer's own default, set explicitly so that processes Nextflow
      # spawns with a rewritten environment still resolve to the same cache.
      APPTAINER_CACHEDIR = "${cacheRoot}/cache";

      # Nextflow reads the SINGULARITY_ name under `singularity.enabled` and
      # the APPTAINER_ name under `apptainer.enabled`; pipelines here use both
      # engine blocks, so both names point at one directory.
      NXF_SINGULARITY_CACHEDIR = "${cacheRoot}/nextflow";
      NXF_APPTAINER_CACHEDIR = "${cacheRoot}/nextflow";

      # SINGULARITY_CACHEDIR is deliberately left unset. apptainer 1.5 honours
      # it but then logs "Environment variable SINGULARITY_CACHEDIR is set, but
      # APPTAINER_CACHEDIR is preferred" on every invocation, which would land
      # in the log of every containerised pipeline task.
    };

    systemd.user.tmpfiles.rules = [
      "d ${cacheRoot} 0700 - - -"
      "d ${cacheRoot}/cache 0700 - - -"
      "d ${cacheRoot}/nextflow 0700 - - -"
    ];
  };
}
