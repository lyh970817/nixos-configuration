{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}:

let
  # Workaround for nixpkgs issue #549906, hit by our pinned nixpkgs
  # b7c2ada (2026-08-05). For a 38-hour window upstream's R generic builder
  # carried `outputChecks.out.disallowedReferences = [ stdenv.cc stdenv.cc.cc ]`
  # (added in 21020ff, PR #542871) alongside a `stripDebugList` that only
  # covered `library/<pname>/libs`. Three packages needed by the rWrapper below
  # keep a compiler path outside that list and so fail the check:
  #   * ps and processx install helper binaries under `library/<pname>/bin`
  #     that escape stripping, and their DWARF records the gcc include dir;
  #   * data.table ships a plain-text `library/data.table/cc` recording
  #     `CC=<gcc-wrapper>/bin/cc`, which stripping cannot reach.
  # This removes the references rather than clearing the check, so the check
  # keeps guarding everything else. Upstream reverted the check wholesale in
  # 0c0b2a4 (PR #549997, 2026-08-07), so delete this whole block once the
  # nixpkgs input is bumped past that commit. Note PR #551056 re-lands the
  # check with `bin` covered but still without a data.table fix, so the
  # data_table override may have to outlive the other two.
  stripPackageBin =
    name: drv:
    drv.overrideAttrs (old: {
      stripDebugList = (old.stripDebugList or [ ]) ++ [ "library/${name}/bin" ];
    });

  # `overrides` is merged into the R package set's fixpoint, so dependents
  # (callr, pkgload, languageserver) pick the fixed packages up. Each override's
  # value has to be taken from a scope where its own fixed dependencies are
  # already in place - processx propagates ps - hence the staged `rWithPs`.
  rWithPs = pkgs.rPackages.override {
    overrides.ps = stripPackageBin "ps" pkgs.rPackages.ps;
  };

  rPackagesFixed = pkgs.rPackages.override {
    overrides = {
      inherit (rWithPs) ps;
      processx = stripPackageBin "processx" rWithPs.processx;
      data_table = rWithPs.data_table.overrideAttrs (old: {
        postFixup = (old.postFixup or "") + ''
          substituteInPlace $out/library/data.table/cc \
            --replace-fail "${pkgs.stdenv.cc}/bin/cc" "cc"
        '';
      });
    };
  };
in

{
  # Development tools and programming languages. Home role only: the remote
  # portable laptop develops over `mosh home`, so it omits this heavy toolchain.
  # Python and yt-dlp are kept on the remote role too since they're useful
  # standalone; yt-dlp also backs the last30days skill's YouTube source.
  config = lib.mkMerge [
    (lib.mkIf (osConfig.portable.role != "home") {
      home.packages = with pkgs; [
        python3
        yt-dlp
      ];
    })
    (lib.mkIf (osConfig.portable.role == "home") {
      home.packages = with pkgs; [
        gnumake
        jdk17
        cargo
        rustc
        go
        nodejs_latest
        neovim-node-client
        sqlite
        (python3.withPackages (
          ps: with ps; [
            pyyaml
          ]
        ))
        python3Packages.pip
        yt-dlp
        uv
        (rWrapper.override {
          packages = with rPackagesFixed; [
            dplyr
            ggplot2
            jsonlite
            data_table
            languageserver
            xml2
          ];
        })
        nextflow
        nf-test
        apptainer
        graphviz
        harper
        marksman
        lua-language-server
        tree-sitter
        typst
        tinymist
        typstyle
        websocat
        ast-grep
        curl
        lua
        luarocks
        vscode-langservers-extracted
        yaml-language-server
        hunspell
        hunspellDicts.en_GB-large
        gemini-cli
        xberg-cli
        digg-pp-cli
        (writeShellScriptBin "zcf" ''
          # Set npm prefix to user's home to avoid read-only errors
          export NPM_CONFIG_PREFIX="$HOME/.npm-global"

          # Add the local bin to PATH so zcf can find tools it installs
          export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"

          # Ensure the directory exists
          mkdir -p "$NPM_CONFIG_PREFIX"

          # Run zcf using npx
          exec ${pkgs.nodejs_22}/bin/npx zcf "$@"
        '')
      ];
    })
  ];
}
