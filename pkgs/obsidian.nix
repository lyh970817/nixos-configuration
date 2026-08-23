{ obsidian, fetchurl }:

# nixpkgs is on 1.12.7, which renders inline math inside callouts through the
# broken pre-1.13.7 path; the explanation vault (home/programs/
# obsidian-explain.nix) needs 1.13.7 or newer. Same official release tarball
# and packaging as nixpkgs, only version and source moved forward. Drop this
# override once nixpkgs reaches 1.13.7.
obsidian.overrideAttrs (old: rec {
  version = "1.13.7";
  name = "obsidian-${version}";
  src = fetchurl {
    url = "https://github.com/obsidianmd/obsidian-releases/releases/download/v${version}/obsidian-${version}.tar.gz";
    hash = "sha256-08vjdcv6QCTbGRC5gZFkn0E0xcSK7l5gtudxOYfc2yg=";
  };
})
