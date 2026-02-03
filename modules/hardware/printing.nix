{ config, pkgs, lib, ... }:

{
  # Enable CUPS for printing
  services.printing.enable = true;
}
