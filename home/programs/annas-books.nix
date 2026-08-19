{ pkgs, ... }:

let
  annasBooks = pkgs.callPackage ../../pkgs/annas-books { };
in
{
  # Books only. Anna's Archive's paper corpus is the same Sci-Hub corpus
  # scansci-oa already reaches for free, and every download here spends one unit
  # of the per-day membership quota -- so this tool is reserved for the case
  # where Anna's Archive is the only option.
  #
  # Membership key: $ANNAS_SECRET_KEY, or ~/.config/annas-books/secret-key with
  # mode 0600 (the client refuses a more permissive file). Kept out of the repo
  # and out of the Nix store deliberately, and never passed as an argument --
  # it travels in a query string, so argv would leak it to `ps`, shell history
  # and logs.
  #
  # Both roles: books are as useful from the laptop as from the desktop.
  home.packages = [ annasBooks ];
}
