{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Keyd keyboard remapping service
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = { };
      };
    };
  };
}
