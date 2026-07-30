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
        settings = {
          main = {
            # Activates the nav layer while CapsLock is held
            capslock = "layer(nav)";
          };
          nav = {
            # Vim-style navigation
            h = "left";
            j = "down";
            k = "up";
            l = "right";

            # Optional: other useful shortcuts on this layer
            u = "pageup";
            d = "pagedown";
            w = "C-right";
            b = "C-left";
            v = "S-right";
          };
        };
      };
    };
  };
}
