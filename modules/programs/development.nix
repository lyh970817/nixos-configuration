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

  # Claude Code ships a foreign dynamically-linked executable on both roles.
  # Keep nix-ld enabled wherever the launcher is installed without restoring
  # the home-only development toolchain on the remote.
  programs.nix-ld.enable = true;

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
