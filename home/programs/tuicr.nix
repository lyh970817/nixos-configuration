{
  lib,
  osConfig,
  pkgs,
  ...
}:

{
  # Interactive code review is currently part of the portable agent workflow.
  config = lib.mkIf (osConfig.portable.role != "home") {
    home.packages = [ pkgs.tuicr ];
  };
}
