---
name: r-dev-shell
description: Set up or repair an R package's dev shell so that Nix provides only R, compilers, system libraries and the devtools bootstrap, while R installs the package's own dependencies into a project-local .R-lib. Invoked manually inside an R project (shell.nix or flake devShell).
disable-model-invocation: true
---

# R Dev Shell

Role split: **Nix** owns R, compilers, system libraries, `pandoc`/`qpdf`/TeX
when `R CMD check` needs them, and `rPackages.devtools` (the one R package
kept in Nix, because it is the installer and its compiled closure is heavy;
it already carries roxygen2, testthat, usethis and pkgload). **R** owns every
package named in `DESCRIPTION`, installed into `.R-lib` at the repo root.

## Process

1. Read `DESCRIPTION`, `shell.nix`/`flake.nix`, `.envrc`, `.Rprofile`,
   `.Rbuildignore`, `.gitignore`. Every `rPackages.*` entry in the shell
   other than `devtools` is a candidate for removal; keep one only when it
   cannot be built by R (not on CRAN/r-universe, or needs a Nix-only
   library). Do not introduce `renv` or `pak` unless asked.

2. For each `rPackages.*` you remove, check whether it compiles against a
   system library and add that library instead (`libxml2` for xml2, `libuv`
   for fs, `openssl`, `curl`, `zlib`, `icu`, `jdk` for rJava, ...).

3. Put this in the shell (`shellHook` of `pkgs.mkShell`; same text in a
   flake devShell). `~/.Renviron` on this host resets `R_LIBS_USER` at every
   R start, so the export alone is not enough; `R_ENVIRON_USER` makes the
   project value win in every R subprocess, `R CMD check` included.
   `devtools::install_dev_deps()` force-updates roxygen2 regardless of its
   `upgrade` argument; `R_REMOTES_UPGRADE=never` stops that.

   ```nix
   buildInputs = [ pkgs.R pkgs.rPackages.devtools pkgs.pandoc pkgs.qpdf ];
   shellHook = ''
     PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
     mkdir -p "$PROJECT_ROOT/.R-lib" "$PROJECT_ROOT/.nix"
     export R_LIBS_USER="$PROJECT_ROOT/.R-lib"
     export R_ENVIRON_USER="$PROJECT_ROOT/.nix/Renviron"
     printf 'R_LIBS_USER=%s\n' "$R_LIBS_USER" > "$R_ENVIRON_USER"
     export R_REMOTES_UPGRADE=never
   '';
   ```

   Keep any existing Bash-default guard (`nix-environment-setup`) after
   these lines. `.envrc` stays `use nix`.

4. Add `.R-lib/` and `.nix/` to `.gitignore`; add `^\.R-lib$`, `^\.R-lib/`,
   `^\.nix$`, `^\.nix/` to `.Rbuildignore`.

## Validation

```sh
nix-shell --run 'Rscript -e '\''stopifnot(.libPaths()[1] == normalizePath(Sys.getenv("R_LIBS_USER")), !any(grepl("/.local/share/R/", .libPaths())), requireNamespace("devtools"))'\'''
```

Do not run the install step yourself unless the user asks: it uses the
network and writes `.R-lib`. Tell the user:

```sh
Rscript -e 'devtools::install_dev_deps(dependencies = TRUE, upgrade = "never")'
```

If it fails with `Configuration failed because <lib> was not found`, that
is the signal to add the system library to the shell, not the R package.
