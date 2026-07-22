{
  lib,
  pkgs,
  ...
}:

{
  # The terminal CLI and Desktop run independently: Desktop owns bundled
  # node_repl while its launcher keeps GUI state out of ~/.codex.
  home.packages = [ pkgs.codex ];

  programs.codexDesktopLinux = {
    enable = true;
    package = pkgs.codex-desktop-isolated;
    cliPackage = null;
  };

  # The Codex engine hardcodes a scan of $HOME/.agents/skills as a user-scope
  # skill source, independent of CODEX_HOME — Desktop's CODEX_HOME/XDG
  # isolation above doesn't stop it from picking up the shared ~/.agents
  # skill set. Disable each ~/.agents skill explicitly in Desktop's own
  # config.toml instead, regenerating a marker-delimited block on every
  # activation so it stays in sync with dotfiles/agents/skills.
  home.activation.codexDesktopDisableAgentsSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    agentsSkillsDir="$HOME/.agents/skills"
    if [[ -d "$agentsSkillsDir" ]]; then
      codexDesktopDir="$HOME/.codex-desktop"
      configFile="$codexDesktopDir/config.toml"
      beginMarker="# BEGIN nixos-config: disable ~/.agents skills"
      endMarker="# END nixos-config: disable ~/.agents skills"

      run ${pkgs.coreutils}/bin/install -d -m 0700 "$codexDesktopDir"
      if [[ ! -e "$configFile" ]]; then
        run ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$configFile"
      fi

      configTmp="$(${pkgs.coreutils}/bin/mktemp "$configFile.XXXXXX")"
      # Marker text contains "/" (in "~/.agents"), so use "|" as the sed
      # address delimiter instead of the default "/".
      ${pkgs.gnused}/bin/sed "\\|^$beginMarker\$|,\\|^$endMarker\$|d" "$configFile" > "$configTmp"

      {
        echo "$beginMarker"
        for skillDir in "$agentsSkillsDir"/*/; do
          [[ -d "$skillDir" ]] || continue
          skillName="$(${pkgs.coreutils}/bin/basename "$skillDir")"
          skillMd="$skillDir/SKILL.md"
          if [[ -f "$skillMd" ]]; then
            fromFrontmatter="$(${pkgs.gnused}/bin/sed -n 's/^name: *//p' "$skillMd" | head -n1)"
            [[ -n "$fromFrontmatter" ]] && skillName="$fromFrontmatter"
          fi
          echo "[[skills.config]]"
          echo "name = \"$skillName\""
          echo "enabled = false"
        done
        echo "$endMarker"
      } >> "$configTmp"

      run ${pkgs.coreutils}/bin/mv -f "$configTmp" "$configFile"
    fi
  '';
}
