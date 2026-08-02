---
name: r-dev-shell
description: R package development shell setup with a project-local R library. Use when configuring shell.nix, flake devShells, .R-lib, R_LIBS_USER, devtools::install_dev_deps(), or moving R package dependencies out of Nix/OS-level tooling into an R-managed local library.
disable-model-invocation: true
---

# R Dev Shell

Use a **role split**: the shell manager provides the development environment; R installs the package dependencies.

## Process

1. Inspect the current setup before editing:
   - Read `DESCRIPTION`, `shell.nix` or `flake.nix`, `.envrc`, `.Rprofile`, `.Rbuildignore`, `.gitignore`, and `git status`.
   - Identify which R packages are package dependencies from `DESCRIPTION` and which are development/review tools.
   - Completion criterion: every R package currently provided by the shell is classified as package dependency, development tool, review tool, or transitive dependency.

2. Preserve the role split:
   - Nix/devShell owns R itself, OS libraries, compilers, `pandoc`, `qpdf`, `pre-commit`, and development/review tools that are intentionally part of the shell.
   - R owns ordinary package dependencies declared in `DESCRIPTION`, installed into the project-local library with `devtools::install_dev_deps(dependencies = TRUE, upgrade = "never")`.
   - Keep `devtools` in the shell when using it as the installer. Keep `roxygen2` in the shell when the repo uses roxygen-generated docs.
   - Duplicates are acceptable when a `DESCRIPTION` package is also intentionally a shell development tool.
   - Do not introduce `renv` or `pak` unless the user asks for lockfile management or a different resolver.
   - Completion criterion: the shell does not mirror runtime `Imports` by default, but all intended development/review tools remain available.

3. Activate a project-local R library from the shell:
   - Prefer `.R-lib` at the repository root.
   - Anchor it with `git rev-parse --show-toplevel` instead of `$PWD`.
   - Hide the global user R library inside the dev shell so missing dependencies fail honestly.
   - Account for R startup resetting `R_LIBS_USER`: set `R_PROFILE_USER` to a generated shell-local profile that enforces `.libPaths()`.
   - Completion criterion: inside the shell, `Sys.getenv("R_LIBS_USER")` and `.libPaths()[1]` both point at repo-root `.R-lib`, and the normal global user library is absent from `.libPaths()`.

Use this `shellHook` pattern:

```sh
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export PROJECT_R_LIB="$PROJECT_ROOT/.R-lib"
export R_LIBS_USER="$PROJECT_R_LIB"
mkdir -p "$PROJECT_R_LIB" "$PROJECT_ROOT/.nix"

export R_PROFILE_USER="$PROJECT_ROOT/.nix/Rprofile"
cat > "$R_PROFILE_USER" <<'EOF'
local_lib <- Sys.getenv("PROJECT_R_LIB")
if (nzchar(local_lib)) {
  dir.create(local_lib, recursive = TRUE, showWarnings = FALSE)
  local_lib <- normalizePath(local_lib, winslash = "/", mustWork = TRUE)
  user_lib <- normalizePath(Sys.getenv("R_LIBS_USER"), winslash = "/", mustWork = FALSE)
  paths <- normalizePath(.libPaths(), winslash = "/", mustWork = FALSE)
  Sys.setenv(R_LIBS_USER = local_lib)
  .libPaths(c(local_lib, paths[paths != user_lib & paths != local_lib]))
}
EOF
```

4. Ignore generated local environment files:
   - Add `.R-lib/` and `.nix/` to `.gitignore`.
   - Add `^\.R-lib$`, `^\.R-lib/`, `^\.nix$`, and `^\.nix/` to `.Rbuildignore`.
   - Completion criterion: the local library and generated R profile cannot be committed accidentally or included in an R package build.

5. Model tool dependencies faithfully:
   - If a custom Nix-built R tool uses `buildRPackage`, put its dependencies in `propagatedBuildInputs`.
   - Do not duplicate every transitive dependency in the top-level shell package list.
   - Completion criterion: each top-level development/review tool and at least one non-top-level propagated dependency load with `requireNamespace()` inside the shell.

## Validation

Run checks equivalent to:

```sh
nix-shell --run 'Rscript -e '\''
cat("R_LIBS_USER=", Sys.getenv("R_LIBS_USER"), "\n", sep = "")
cat("PROJECT_R_LIB=", Sys.getenv("PROJECT_R_LIB"), "\n", sep = "")
print(.libPaths()[1:5])
stopifnot(
  normalizePath(Sys.getenv("R_LIBS_USER"), winslash = "/", mustWork = TRUE) ==
    normalizePath(Sys.getenv("PROJECT_R_LIB"), winslash = "/", mustWork = TRUE)
)
stopifnot(
  normalizePath(.libPaths()[1], winslash = "/", mustWork = TRUE) ==
    normalizePath(Sys.getenv("PROJECT_R_LIB"), winslash = "/", mustWork = TRUE)
)
'\'''
```

Also validate intended shell tools:

```sh
nix-shell --run 'Rscript -e '\''for (pkg in c("devtools", "roxygen2")) stopifnot(requireNamespace(pkg, quietly = TRUE))'\'''
```

For custom development tools, include their package names and one propagated dependency, for example:

```sh
nix-shell --run 'Rscript -e '\''for (pkg in c("goodpractice", "cyclocomp")) stopifnot(requireNamespace(pkg, quietly = TRUE))'\'''
```

Do not run `devtools::install_dev_deps()` unless the user wants dependencies installed now; it may use network and mutate `.R-lib`.

## User-Facing Command

Print or document this command as the explicit package dependency step:

```sh
Rscript -e 'devtools::install_dev_deps(dependencies = TRUE, upgrade = "never")'
```
