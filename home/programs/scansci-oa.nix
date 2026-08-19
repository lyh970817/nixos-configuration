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
  # cookies and profiles all live under one XDG-shaped directory.
  dataDir = "${config.xdg.dataHome}/scansci-oa";

  scansciOa = pkgs.callPackage ../../pkgs/scansci-oa.nix {
    scansci-pdf = scansciPdf;
    inherit dataDir;
  };

  # Everything that would reach an institution, a browser, or a runtime binary
  # download is pinned off. use_tor_for_scihub in particular: upstream would
  # fetch a Tor Expert Bundle tarball, a prebuilt glibc binary that cannot run on
  # NixOS (pkgs/scansci-pdf.nix patches that path out as well).
  settings = {
    download_strategy = "grey_only";
    use_tor_for_scihub = false;
    carsi_enabled = false;
    vpnsci_enabled = false;
    ezproxy_enabled = false;
    chrome_profile_dir = "";
    elsevier_api_key = "";
  };
in
{
  # Both roles: paper retrieval is as useful from the laptop as from the desktop,
  # and the closure is pure Python.
  home.packages = [ scansciOa ];

  xdg.dataFile."scansci-oa/config.json".text = builtins.toJSON settings;
}
