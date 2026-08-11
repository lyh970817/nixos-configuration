{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Bindings every keyboard gets. keyd picks exactly one config file per
  # device and an explicit id outranks the `*` wildcard, so a per-device
  # config replaces these rather than merging with them -- hence the reuse.
  commonSettings = {
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
      y = "scrollup";
      e = "scrolldown";
      w = "C-right";
      b = "C-left";
      v = "S-right";
    };
  };
in
{
  # Keyd keyboard remapping service
  services.keyd = {
    enable = true;
    keyboards = {
      default = {
        ids = [ "*" ];
        settings = commonSettings;
      };

      # SANWA BT KEYBOARD (Bluetooth) carries Alt and Super in Mac order,
      # i.e. swapped relative to a PC keyboard; swap them back. The `k:`
      # prefix keeps the match on the keyboard node only.
      sanwa-bt = {
        ids = [ "k:04e8:7021" ];
        settings = lib.recursiveUpdate commonSettings {
          main = {
            leftalt = "layer(meta)";
            leftmeta = "layer(alt)";
            rightalt = "layer(meta)";
            rightmeta = "layer(alt)";
          };
        };
      };
    };
  };
}
