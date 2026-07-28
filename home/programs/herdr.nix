{
  config,
  osConfig,
  pkgs,
  ...
}:

let
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";
in
{
  # Terminal agent multiplexer; useful on both roles, so it is not gated on
  # `portable.role`. The package comes from the pinned upstream flake input
  # via the overlay in flake.nix.
  home.packages = [ pkgs.herdr ];

  # herdr rewrites its own config.toml at runtime: `mark_onboarding_complete`
  # clears the first-run wizard and the in-app Settings screen saves through the
  # same path. A read-only /nix/store copy makes the wizard reappear on every
  # launch and makes Settings fail silently, so the authored config is an
  # out-of-store symlink into this repo — writes go through to
  # dotfiles/herdr/config.toml and stay in version control. Safe because the
  # writer is a plain in-place `fs::write` (src/app/config_io.rs), not
  # temp-file+rename, so it follows the link instead of replacing it.
  #
  # Only config.toml is linked, never the whole directory: herdr resolves its
  # data dir from `config_dir()` independently of the config file's location and
  # drops herdr.log, herdr-client.log, herdr-server.log, plugins.json,
  # session.json and its sockets in there. Home Manager materializes
  # ~/.config/herdr as a real directory when only a nested path is managed, so
  # that runtime state stays writable and out of the repo.
  #
  # See dotfiles/herdr/config.toml for the layout and theme rationale.
  xdg.configFile."herdr/config.toml".source = link "dotfiles/herdr/config.toml";
}
