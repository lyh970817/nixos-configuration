{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";
in
{
  home.file.".omp/agent/themes/matrix.json".source = link "dotfiles/omp/themes/matrix.json";
  home.file.".omp/profiles/mattpocock/agent/themes/matrix.json".source =
    link "dotfiles/omp/themes/matrix.json";
  home.file.".omp/agent/lsp.json".source = link "dotfiles/omp/lsp.json";
  home.file.".omp/agent/skills" = {
    source = link "dotfiles/omp/skills";
    force = true;
  };

  # OMP owns config.yml and rewrites it at runtime. Seed it only when absent,
  # then reconcile repository-owned leaves without replacing runtime state.
  home.activation.ompTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    omp_config_dir="$HOME/.omp/agent"
    omp_config="$omp_config_dir/config.yml"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$omp_config_dir"
    if [ ! -e "$omp_config" ]; then
      run ${pkgs.coreutils}/bin/install -m 0600 \
        ${../../dotfiles/omp/config.yml} "$omp_config"
    fi

    omp_config_tmp="$(${pkgs.coreutils}/bin/mktemp "$omp_config.XXXXXX")"
    trap 'rm -f "$omp_config_tmp"' EXIT
    ${pkgs.yq-go}/bin/yq '
      .theme.dark = "matrix"
      | .theme.light = "light"
      | .symbolPreset = "nerd"
      | .skills.enableCodexUser = false
      | .skills.enablePiUser = true
      | .compaction.enabled = true
      | .compaction.strategy = "context-full"
      | .compaction.remoteEnabled = true
      | .compaction.remoteStreamingV2Enabled = true
      | .task.maxRecursionDepth = 3
      | .task.enableEffort = true
    ' "$omp_config" > "$omp_config_tmp"
    run ${pkgs.coreutils}/bin/chmod 0600 "$omp_config_tmp"
    run ${pkgs.coreutils}/bin/mv -f "$omp_config_tmp" "$omp_config"
    trap - EXIT
  '';

  # Keep the Matt Pocock profile isolated from the Codex user-skill source.
  # Marketplace state and installed plugin contents stay OMP-managed.
  home.activation.ompMattPocockProfile = lib.hm.dag.entryAfter [ "ompTheme" ] ''
    omp_config_dir="$HOME/.omp/profiles/mattpocock/agent"
    omp_config="$omp_config_dir/config.yml"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$omp_config_dir"

    if [ ! -e "$omp_config" ]; then
      run ${pkgs.coreutils}/bin/install -m 0600 \
        ${../../dotfiles/omp/profiles/mattpocock/config.yml} "$omp_config"
    fi

    omp_config_tmp="$(${pkgs.coreutils}/bin/mktemp "$omp_config.XXXXXX")"
    trap 'rm -f "$omp_config_tmp"' EXIT
    ${pkgs.yq-go}/bin/yq '
      .theme.dark = "matrix"
      | .theme.light = "light"
      | .symbolPreset = "nerd"
      | .skills.enableCodexUser = false
      | .skills.enablePiUser = true
      | .compaction.enabled = true
      | .compaction.strategy = "context-full"
      | .compaction.remoteEnabled = true
      | .compaction.remoteStreamingV2Enabled = true
      | .task.maxRecursionDepth = 3
      | .task.enableEffort = true
    ' "$omp_config" > "$omp_config_tmp"
    run ${pkgs.coreutils}/bin/chmod 0600 "$omp_config_tmp"
    run ${pkgs.coreutils}/bin/mv -f "$omp_config_tmp" "$omp_config"
    trap - EXIT
  '';
}
