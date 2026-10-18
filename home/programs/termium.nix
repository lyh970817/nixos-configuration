{
  config,
  lib,
  pkgs,
  ...
}:

let
  bundle = "${pkgs.termium}/lib/termium";
  # Termium finds its bundle from its own resolved executable path and locks
  # a session with a .active file beside bin/. This root keeps a real copy of
  # the client and links everything else back to the store.
  app = "${config.xdg.stateHome}/termium/app";
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "termium" ''
      exec "${app}/bin/termium" "$@"
    '')
  ];

  home.activation.termiumAppRoot = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${app}/bin"
    for entry in ${bundle}/*; do
      name="''${entry##*/}"
      [ "$name" = bin ] || run ln -sfn "$entry" "${app}/$name"
    done
    if ! ${pkgs.diffutils}/bin/cmp -s ${bundle}/bin/termium "${app}/bin/termium"; then
      # Rename over the old client so a running session keeps its inode.
      run install -m755 ${bundle}/bin/termium "${app}/bin/.termium.new"
      run mv -f "${app}/bin/.termium.new" "${app}/bin/termium"
    fi
  '';
}
