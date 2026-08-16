{ pkgs, ... }:

{
  # Read-only Xiaohongshu client, `xhs`. `xhs favorites --json` / `--yaml` is
  # the path to a structured dump of saved notes. Both roles.
  #
  # Auth needs no wrapper: the session lives in ~/.xiaohongshu-cli/cookies.json
  # (written by `xhs login`, which renders its QR code in the terminal), or is
  # lifted from a browser with `xhs --cookie-source brave`. The camoufox
  # browser-assisted login variant is not packaged -- see pkgs/xiaohongshu-cli.nix.
  home.packages = [ pkgs.xiaohongshu-cli ];
}
