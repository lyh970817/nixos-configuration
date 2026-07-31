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

  # OMP owns config.yml and rewrites it at runtime. Seed it from a copied
  # template, then reconcile only settings this repository intentionally owns.
  home.activation.ompTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    omp_config_dir="$HOME/.omp/agent"
    omp_config="$omp_config_dir/config.yml"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$omp_config_dir"
    if [ ! -e "$omp_config" ]; then
      run ${pkgs.coreutils}/bin/install -m 0600 \
        ${../../dotfiles/omp/config.yml} "$omp_config"
    fi

    run ${pkgs.yq-go}/bin/yq -i '.theme.dark = "matrix" | .skills.enableCodexUser = false | .skills.enablePiUser = true | .skills.ignoredSkills = ["lavish", "r-dev-shell"]' "$omp_config"

    run ${pkgs.coreutils}/bin/chmod 0600 "$omp_config"
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

    run ${pkgs.yq-go}/bin/yq -i '.theme.dark = "matrix" | .skills.enableCodexUser = false | .skills.enablePiUser = true' "$omp_config"

    run ${pkgs.coreutils}/bin/chmod 0600 "$omp_config"
  '';
}
