{ config, pkgs, lib, ... }:

{
  # Development tools and utilities
  programs.direnv.enable = true;
  programs.direnv.nix-direnv.enable = true;

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

  environment.systemPackages = with pkgs; [
    playwright-driver.browsers
  ];

  environment.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
  };
}
