{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

# Bidirectional LaTeX <-> Typst converter. Installed for the `t2l` CLI, which
# the explanation workflow's Neovim keymap pipes visual selections through to
# turn terse Typst math into the pure LaTeX the explanation documents require.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tylax";
  version = "0.3.7";

  src = fetchFromGitHub {
    owner = "scipenai";
    repo = "tylax";
    tag = "v${finalAttrs.version}";
    hash = "sha256-XwgSBEJ0Y9Tuxivlizht7uGaRJMI45vZhaXZBVXxbTI=";
  };

  # Vendored lockfile (copied from the tagged source): importCargoLock fetches
  # each crate through fetchurl, which crates.io accepts, whereas the
  # cargoHash vendor tool's requests are rejected with 403 through the proxy.
  cargoLock.lockFile = ./Cargo.lock;

  # The workspace also carries Python bindings (bindings/python); only the
  # main crate with its `t2l` binary is wanted.
  cargoBuildFlags = [
    "--package"
    "tylax"
  ];
  cargoTestFlags = [
    "--package"
    "tylax"
  ];

  meta = {
    description = "Bidirectional AST-based LaTeX <-> Typst converter";
    homepage = "https://github.com/scipenai/tylax";
    license = lib.licenses.asl20;
    mainProgram = "t2l";
    platforms = lib.platforms.linux;
  };
})
