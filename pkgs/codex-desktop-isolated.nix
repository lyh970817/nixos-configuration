{
  codexDesktopPackage,
  makeWrapper,
  symlinkJoin,
}:

symlinkJoin {
  name = "codex-desktop-isolated";
  paths = [ codexDesktopPackage ];
  nativeBuildInputs = [ makeWrapper ];

  postBuild = ''
    rm -f "$out/bin/codex-desktop"
    makeWrapper "${codexDesktopPackage}/bin/codex-desktop" "$out/bin/codex-desktop" \
      --run 'export CODEX_HOME="$HOME/.codex-desktop"' \
      --run 'export XDG_CONFIG_HOME="$HOME/.config/codex-desktop"' \
      --run 'export XDG_DATA_HOME="$HOME/.local/share/codex-desktop"' \
      --run 'export XDG_CACHE_HOME="$HOME/.cache/codex-desktop"'

    desktopFile="$out/share/applications/codex-desktop.desktop"
    target="$(readlink -f "$desktopFile")"
    rm -f "$desktopFile"
    substitute "$target" "$desktopFile" \
      --replace-fail "${codexDesktopPackage}/bin/codex-desktop" "$out/bin/codex-desktop"
  '';
}
