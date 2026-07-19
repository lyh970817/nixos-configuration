{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Enable graphics acceleration
  # No GPU-specific video driver is forced; Mesa/DRM autodetect per machine.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
