# R Language Configuration
# Managed by home-manager
# Original: ~/.Rprofile, ~/.Renviron
{ config, pkgs, ... }:

{
  home.file = {
    ".Rprofile".text = ''
      options(
        languageserver.server_capabilities =
          list(
            hoverProvider = FALSE,
            signatureHelpProvider = FALSE,
            completionProvider = FALSE,
            completionItemResolve = FALSE
          )
      )
    '';

    ".Renviron".text = ''
      R_LIBS_USER=~/.local/share/R/library/%v
    '';
  };
}
