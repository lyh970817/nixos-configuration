{ pkgs, ... }:

{
  # Ungated: both roles run Hyprland and both already carry grim/slurp, and the
  # wrapper picks its encoder at runtime, so the laptop's weaker VA-API support
  # is handled inside the script rather than by leaving the tool off the role.
  home.packages = [ pkgs.screen-record ];
}
