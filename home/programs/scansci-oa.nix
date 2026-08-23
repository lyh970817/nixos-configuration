{
  config,
  pkgs,
  ...
}:

let
  # Deliberately kept out of the flake overlay and out of home.packages: the only
  # supported entry point is the `scansci-oa` wrapper, which pins the data
  # directory and the subcommand. Putting bin/scansci-pdf on PATH would expose
  # `login`, `fetch`, `federated-login`, `publisher-batch` and `import-cookies`,
  # all of which drive the institutional ladder or launch a browser.
  scansciPdf = pkgs.python3Packages.callPackage ../../pkgs/scansci-pdf.nix { };

  # Isolated from the upstream default (~/.scansci-pdf) so config, cache,
  # cookies and profiles all live under one XDG-shaped directory. The wrapper
  # runs each of its two passes out of its own subdirectory of this root.
  dataDir = "${config.xdg.dataHome}/scansci-oa";

  scansciOa = pkgs.callPackage ../../pkgs/scansci-oa.nix {
    scansci-pdf = scansciPdf;
    inherit dataDir;
  };

  # Everything that would reach an institution, a browser, or a runtime binary
  # download is pinned off. use_tor_for_scihub in particular: upstream would
  # fetch a Tor Expert Bundle tarball, a prebuilt glibc binary that cannot run on
  # NixOS (pkgs/scansci-pdf.nix patches that path out as well).
  safety = {
    use_tor_for_scihub = false;
    carsi_enabled = false;
    vpnsci_enabled = false;
    ezproxy_enabled = false;
    chrome_profile_dir = "";
    elsevier_api_key = "";
  };

  # One config per pass. download_strategy is the only difference; the wrapper
  # selects a pass by picking its data directory, so no strategy string is ever
  # forwarded to the CLI. grey_only never falls back to open access on its own,
  # which is exactly why the wrapper needs a second pass.
  passConfig = strategy: builtins.toJSON (safety // { download_strategy = strategy; });
in
{
  # Both roles: paper retrieval is as useful from the laptop as from the desktop,
  # and the closure is pure Python.
  home.packages = [ scansciOa ];

  xdg.dataFile."scansci-oa/grey/config.json".text = passConfig "grey_only";
  xdg.dataFile."scansci-oa/oa/config.json".text = passConfig "legal_only";
}
