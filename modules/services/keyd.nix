{ config, pkgs, lib, ... }:

{
  # Keyd keyboard remapping service
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = {
          main = {
            # Maps CapsLock to 'nav' layer when held, Esc when tapped
            capslock = "overload(nav, esc)";
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
          };
        };
      };
    };
  };
}
