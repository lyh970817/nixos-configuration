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
  home.file.".omp/agent/lsp.json".source = link "dotfiles/omp/lsp.json";

  # OMP owns config.yml and rewrites it at runtime. Update only the selected
  # dark theme, leaving its other settings and all mutable state untouched.
  home.activation.ompTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    omp_config_dir="$HOME/.omp/agent"
    omp_config="$omp_config_dir/config.yml"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$omp_config_dir"

    if [ -e "$omp_config" ]; then
      run ${pkgs.yq-go}/bin/yq -i '.theme.dark = "matrix"' "$omp_config"
    else
      run ${pkgs.yq-go}/bin/yq -n '.theme.dark = "matrix"' > "$omp_config"
    fi

    run ${pkgs.coreutils}/bin/chmod 0600 "$omp_config"
  '';
}
