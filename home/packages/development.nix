{
  config,
  pkgs,
  lib,
  osConfig,
  ...
}:

{
  # Development tools and programming languages. Home role only: the remote
  # portable laptop develops over `mosh home`, so it omits this heavy toolchain.
  config = lib.mkIf (osConfig.portable.role == "home") {
    home.packages = with pkgs; [
      gcc
      gnumake
      jdk17
      cargo
      rustc
      go
      nodejs_latest
      nodePackages.neovim
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
        packages = with rPackages; [
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
      nixfmt
      nil
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
      nodePackages.vscode-langservers-extracted
      hunspell
      hunspellDicts.en_GB-large
      gemini-cli
      kreuzberg-cli
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
  };
}
