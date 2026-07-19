{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Development tools and utilities
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

  # nix-ld only matters for running foreign dynamically-linked dev binaries;
  # the remote does its development over `mosh home`, so gate it to home.
  programs.nix-ld.enable = lib.mkIf (config.portable.role == "home") true;

  programs.ssh.startAgent = lib.mkForce false;

  programs.localsend = {
    enable = true;
    openFirewall = true;
  };

  programs.nm-applet.enable = true;
  programs.thunar.enable = true;
  programs.dconf.enable = true;

  # Additional services
  services.tumbler.enable = true;
  services.gvfs.enable = true;

  # Playwright browsers are a browser-automation testing dependency (home dev
  # only). Note the same PLAYWRIGHT_* env vars are also set unconditionally in
  # modules/desktop/hyprland.nix; matching values merge cleanly.
  environment.systemPackages = lib.mkIf (config.portable.role == "home") (
    with pkgs;
    [
      playwright-driver.browsers
    ]
  );

  environment.sessionVariables = lib.mkIf (config.portable.role == "home") {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };
}
