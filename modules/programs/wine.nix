# Wine support for running Windows applications
{ config, pkgs, lib, ... }:

{
  # Enable 32-bit graphics libraries (required for Wine)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
