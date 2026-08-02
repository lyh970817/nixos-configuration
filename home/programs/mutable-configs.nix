{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  # Hand-edited configs we want to (1) edit without a rebuild and (2) keep in
  # git and carried onto a fresh install. mkOutOfStoreSymlink points $HOME at
  # the working tree in the config repo (portable.configDir) instead of a
  # read-only /nix/store copy, so edits are live and land in version control.
  #
  # Only the authored subpaths below are linked. Machine-local base config,
  # secrets, session history, and caches stay mutable and unmanaged in place
  # (e.g. ~/.codex/config.toml, ~/.codex/auth.json,
  # ~/.config/claude/.credentials.json, projects/, sessions/, sqlite logs).
  #
  # Directory links are robust: files the app creates or rewrites inside them
  # land in the repo. Single-file links (AGENTS.md, CLAUDE.md, statusline.sh)
  # can be replaced by a real file if the owning app rewrites
  # them via a temp-file+rename; if that happens, re-run `nixos-rebuild switch`
  # to restore the link. Claude settings are ordinary mutable files: activation
  # seeds missing files and reconciles only the explicitly owned JSON leaves.
  # Theme is supplied per session by the launcher (see home/programs/claude.nix).
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";
  claudeEnvironment = ../../dotfiles/claude/environment.json;
  claudeMarketplaces = ../../dotfiles/claude/marketplaces.json;
  claudeProfiles = [
    {
      name = "standard";
      configDir = ".config/claude";
      settings = ../../dotfiles/claude/settings.json;
    }
    {
      name = "mattpocock";
      configDir = ".config/claude-mattpocock";
      settings = ../../dotfiles/claude-mattpocock/settings.json;
    }
    {
      name = "gpt56";
      configDir = ".config/claude-gpt56";
      settings = ../../dotfiles/claude-gpt56/settings.json;
    }
  ];

  codexProfileNames = [
    "last30days"
    "lavish-axi"
    "mattpocock"
    "superpowers"
    "understand-anything-codegraph"
  ];

  codexSkillNames = [
    "nix-environment-setup"
    "bro"
    "agent-config-setup"
    "sync-mattpocock-skills"
    "codex-dynamic-workflows"
    "commit-guidelines"
    "domain-context"
    "lavish"
    "r-dev-shell"
    "root-browser-control"
    "superpowers-domain-context"
    "visual-verification"
  ];

  codexMattpocockSkillNames = [
    "ask-matt"
    "code-review"
    "codebase-design"
    "diagnosing-bugs"
    "grill-me"
    "grill-with-docs"
    "grilling"
    "handoff"
    "implement"
    "improve-codebase-architecture"
    "loop-me"
    "prototype"
    "research"
    "resolving-merge-conflicts"
    "setup-matt-pocock-skills"
    "setup-pre-commit"
    "tdd"
    "to-spec"
    "to-tickets"
    "triage"
    "wayfinder"
    "wizard"
    "writing-great-skills"
  ];

  codexSkillLinks = lib.listToAttrs (
    (map (name: {
      name = ".codex/skills/${name}";
      value = {
        source = link "dotfiles/codex/skills/${name}";
        force = true;
      };
    }) codexSkillNames)
    ++ (map (name: {
      name = ".codex/skills/mattpocock/${name}";
      value = {
        source = link "dotfiles/codex/skills/mattpocock/${name}";
        force = true;
      };
    }) codexMattpocockSkillNames)
  );
  codexReconcile = pkgs.writeText "codex-reconcile.py" ''
    import argparse
    import json
    import os
    import re
    import stat
    import tempfile
    import tomllib

    HEADER = re.compile(r"^\s*(\[\[?)([^\]]+)(\]\]?)\s*(?:#.*)?$")
    PLUGINS = [
        "browser@openai-bundled",
        "computer-use@openai-bundled",
        "sites@openai-bundled",
        "visualize@openai-bundled",
        "deep-research@openai-bundled",
    ]
    SKILLS = [
        "control-in-app-browser",
        "visualize",
        "sites-hosting",
        "sites-building",
        "deep-research",
        "openai-templates",
        "google-drive",
        "google-drive:google-drive",
        "google-drive:google-drive-comments",
        "google-drive:google-docs",
        "google-drive:google-sheets",
        "google-drive:google-slides",
    ]
    PATH_SKILLS = {
        "control-in-app-browser": "control-in-app-browser",
        "sites-hosting": "sites-hosting",
        "sites-building": "sites-building",
        "deep-research": "deep-research",
        "openai-templates": "openai-templates",
        "google-drive": "google-drive",
    }

    def value(item):
        return json.dumps(item, separators=(",", ":"))

    def headers(lines):
        for index, line in enumerate(lines):
            match = HEADER.match(line.rstrip("\n"))
            if match:
                yield index, match.group(1), match.group(2).strip()

    def bounds(lines, index):
        end = len(lines)
        for candidate, _, _ in headers(lines):
            if candidate > index:
                end = candidate
                break
        return index, end

    def append_block(lines, rows):
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip():
            lines.append("\n")
        lines.extend(row + "\n" for row in rows)

    def table_key(lines, table, key, rendered):
        pattern = re.compile(r"^\s*%s\s*=" % re.escape(key))
        if not table:
            for index, line in enumerate(lines):
                if HEADER.match(line.rstrip("\n")):
                    break
                if pattern.match(line):
                    replacement = "%s = %s\n" % (key, rendered)
                    if line == replacement:
                        return False
                    lines[index] = replacement
                    return True
            lines.insert(0, "%s = %s\n" % (key, rendered))
            return True
        table_index = None
        for index, opening, name in headers(lines):
            if opening == "[" and name == table:
                table_index = index
                break
        if table_index is None:
            append_block(lines, ["[%s]" % table, "%s = %s" % (key, rendered)])
            return True
        start, end = bounds(lines, table_index)
        pattern = re.compile(r"^\s*%s\s*=" % re.escape(key))
        for index in range(start + 1, end):
            if pattern.match(lines[index]):
                replacement = "%s = %s\n" % (key, rendered)
                if lines[index] == replacement:
                    return False
                lines[index] = replacement
                return True
        lines.insert(start + 1, "%s = %s\n" % (key, rendered))
        return True

    def skill_blocks(lines):
        starts = [
            index for index, opening, name in headers(lines)
            if opening == "[[" and name == "skills.config"
        ]
        for offset, start in enumerate(starts):
            yield start, starts[offset + 1] if offset + 1 < len(starts) else len(lines)

    def quoted_field(lines, start, end, field):
        pattern = re.compile(r"^\s*%s\s*=\s*([\"'])(.*?)\1" % field)
        for index in range(start + 1, end):
            match = pattern.match(lines[index])
            if match:
                return index, match.group(2)
        return None, None

    def set_enabled(lines, start, end, enabled):
        rendered = "true" if enabled else "false"
        pattern = re.compile(r"^\s*enabled\s*=")
        for index in range(start + 1, end):
            if pattern.match(lines[index]):
                replacement = "enabled = %s\n" % rendered
                if lines[index] == replacement:
                    return False
                lines[index] = replacement
                return True
        lines.insert(start + 1, "enabled = %s\n" % rendered)
        return True

    def atomic_write(path, content):
        directory = os.path.dirname(path) or "."
        os.makedirs(directory, mode=0o700, exist_ok=True)
        mode = stat.S_IMODE(os.stat(path).st_mode) if os.path.exists(path) else 0o600
        fd, temporary = tempfile.mkstemp(prefix=".%s." % os.path.basename(path), dir=directory)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary, mode)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def reconcile_base(path):
        try:
            old = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
        except OSError as error:
            print("warning: cannot read Codex config %s: %s" % (path, error))
            return
        if old:
            try:
                tomllib.loads(old)
            except tomllib.TOMLDecodeError as error:
                print("warning: leaving malformed Codex config untouched: %s: %s" % (path, error))
                return
        lines = old.splitlines(True)
        changed = table_key(lines, "features", "remote_plugin", "false")
        for plugin in PLUGINS:
            changed = table_key(lines, 'plugins."%s"' % plugin, "enabled", "false") or changed
        present = set()
        for start, end in skill_blocks(lines):
            name_index, name = quoted_field(lines, start, end, "name")
            path_index, skill_path = quoted_field(lines, start, end, "path")
            selected = name if name in SKILLS else None
            if selected is None and skill_path:
                for marker, stable in PATH_SKILLS.items():
                    if "/" + marker + "/" in skill_path or skill_path.endswith("/" + marker + "/SKILL.md"):
                        selected = stable
                        break
            if selected is None:
                continue
            present.add(selected)
            if path_index is not None:
                lines[path_index] = 'name = "%s"\n' % selected
                changed = True
            changed = set_enabled(lines, start, end, False) or changed
        for skill in SKILLS:
            if skill not in present:
                append_block(lines, [
                    "[[skills.config]]",
                    'name = "%s"' % skill,
                    "enabled = false",
                ])
                changed = True
        new = "".join(lines)
        if changed and new != old:
            try:
                tomllib.loads(new)
            except tomllib.TOMLDecodeError as error:
                raise SystemExit("Codex policy reconciliation produced invalid TOML: %s" % error)
            atomic_write(path, new)

    def reconcile_profile(template_path, path):
        with open(template_path, encoding="utf-8") as handle:
            policy_text = handle.read()
        policy = tomllib.loads(policy_text)
        if os.path.exists(path):
            try:
                with open(path, encoding="utf-8") as handle:
                    old = handle.read()
                tomllib.loads(old)
            except (OSError, tomllib.TOMLDecodeError) as error:
                print("warning: leaving malformed Codex profile untouched: %s: %s" % (path, error))
                return
        else:
            old = ""
        if not old:
            atomic_write(path, policy_text)
            return
        lines = old.splitlines(True)
        changed = False
        for key in ("model", "model_reasoning_effort"):
            if key in policy:
                changed = table_key(lines, "", key, value(policy[key])) or changed
        for plugin, settings in policy.get("plugins", {}).items():
            for key, setting in settings.items():
                changed = table_key(lines, 'plugins."%s"' % plugin, key, value(setting)) or changed
        for server, settings in policy.get("mcp_servers", {}).items():
            for key, setting in settings.items():
                changed = table_key(lines, "mcp_servers.%s" % server, key, value(setting)) or changed
        desired = policy.get("skills", {}).get("config", [])
        desired_names = {entry.get("name") for entry in desired}
        existing = set()
        stale_blocks = []
        for start, end in skill_blocks(lines):
            _, name = quoted_field(lines, start, end, "name")
            if name == "last30days" and name not in desired_names:
                stale_blocks.append((start, end))
                continue
            if name is None:
                continue
            for entry in desired:
                if entry.get("name") == name:
                    existing.add(name)
                    if "enabled" in entry:
                        changed = set_enabled(lines, start, end, bool(entry["enabled"])) or changed
                    break
        if stale_blocks:
            stale_lines = {
                index
                for start, end in stale_blocks
                for index in range(start, end)
            }
            lines = [
                line for index, line in enumerate(lines)
                if index not in stale_lines
            ]
            changed = True
        for entry in desired:
            if entry.get("name") not in existing:
                append_block(lines, [
                    "[[skills.config]]",
                    'name = "%s"' % entry["name"],
                    "enabled = %s" % ("true" if entry.get("enabled") else "false"),
                ])
                changed = True
        new = "".join(lines)
        if changed and new != old:
            tomllib.loads(new)
            atomic_write(path, new)

    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--profile", nargs=2, action="append", default=[])
    args = parser.parse_args()
    if args.base:
        reconcile_base(args.base)
    for template, target in args.profile:
        reconcile_profile(template, target)
  '';
in
{
  # Keep tracked Claude policy separate from ordinary mutable per-profile
  # settings files. Missing files are seeded; existing files are reconciled
  # field-by-field and atomically replaced only when valid.
  # Claude settings are ordinary mutable files. Missing files are seeded from
  # the tracked policy; existing parseable files receive only owned leaves.
  # Migrate away from the old directory-level links before Home Manager
  # creates the individual authored-resource links below. Otherwise the
  # activation can follow a legacy link into the repository and rewrite the
  # source tree with links back to the new generation.
  home.activation.removeLegacyAgentDirectoryLinks =
    lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      for legacy_link in \
        "$HOME/.codex/rules" \
        "$HOME/.codex/skills" \
        "$HOME/.config/claude/skills"; do
        if [ -L "$legacy_link" ]; then
          run ${pkgs.coreutils}/bin/rm -f "$legacy_link"
        fi
      done
    '';

  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    claude_jq=${pkgs.jq}/bin/jq
    claude_environment=${lib.escapeShellArg (toString claudeEnvironment)}
    claude_marketplaces=${lib.escapeShellArg (toString claudeMarketplaces)}

    claude_reconcile() {
      input="$1"
      output="$2"
      profile_template="$3"
      profile_name="$4"
      "$claude_jq" \
        --slurpfile environment "$claude_environment" \
        --slurpfile template "$profile_template" \
        --slurpfile manifest "$claude_marketplaces" \
        --arg profile "$profile_name" \
        '
          ($template[0]) as $template |
          ($environment[0]) as $environment |
          ($manifest[0][$profile]) as $profile_policy |
          if ($environment | type) != "object"
             or ($template | type) != "object"
             or ($profile_policy | type) != "object"
          then error("Claude policy must contain JSON objects")
          else
            .env = $environment |
            .permissions = if (.permissions | type) == "object" then .permissions else {} end |
            .permissions.allow = $template.permissions.allow |
            .permissions.deny = $template.permissions.deny |
            .skipDangerousModePermissionPrompt = $template.skipDangerousModePermissionPrompt |
            .statusLine = $template.statusLine |
            .extraKnownMarketplaces =
              (
                if (.extraKnownMarketplaces | type) == "object"
                then .extraKnownMarketplaces
                else {}
                end |
                reduce (($profile_policy.marketplaces // {}) | to_entries[]) as $marketplace
                  (.;
                    .[$marketplace.key] = {
                      source: {
                        source: "github",
                        repo: $marketplace.value.repo
                      }
                    })
              ) |
            .enabledPlugins =
              (
                if (.enabledPlugins | type) == "object"
                then .enabledPlugins
                else {}
                end |
                reduce (($profile_policy.plugins // {}) | to_entries[]) as $plugin
                  (.;
                    .[$plugin.key] = $plugin.value)
              ) |
            if ($profile == "mattpocock" or $profile == "gpt56") then
              del(.enabledPlugins["last30days@last30days-skill"]) |
              del(.extraKnownMarketplaces["last30days-skill"])
            else .
            end |
            if ($profile == "gpt56") then
              .availableModels = $template.availableModels |
              .modelOverrides = $template.modelOverrides
            else .
            end
          end
        ' "$input" > "$output"
    }

    claude_handle_failure() {
      failure_output="$1"
      failure_status="$2"
      if printf '%s\n' "$failure_output" \
        | ${pkgs.gnugrep}/bin/grep -Eiq \
          'network|dns|resolve|github|remote|timed[ -]?out|timeout|connection|fetch|tls|temporar|unavailable|clone|premature|out[ -]?of[ -]?date|already (enabled|installed|exists)|502|503|429'; then
        echo "warning: transient Claude marketplace failure (status $failure_status); will retry on next activation: $failure_output" >&2
        return 0
      fi
      echo "error: Claude marketplace/plugin command failed (status $failure_status): $failure_output" >&2
      return 1
    }

    claude_bootstrap() {
      claude_profile_name="$1"
      claude_config_dir="$2"
      export CLAUDE_CONFIG_DIR="$HOME/$claude_config_dir"
      claude_marketplace_degraded=0

      while IFS="$(printf '\t')" read -r marketplace_name marketplace_source; do
        [ -n "$marketplace_name" ] || continue
        if marketplace_list="$(${pkgs.claude-code}/bin/claude plugin marketplace list 2>&1)"; then
          :
        else
          marketplace_status="$?"
          if claude_handle_failure "$marketplace_list" "$marketplace_status"; then
            claude_marketplace_degraded=1
            continue
          else
            return 1
          fi
        fi
        if ! printf '%s\n' "$marketplace_list" | ${pkgs.gnugrep}/bin/grep -Fq "$marketplace_name"; then
          if marketplace_add="$(${pkgs.claude-code}/bin/claude plugin marketplace add "$marketplace_source" 2>&1)"; then
            :
          else
            marketplace_status="$?"
            if claude_handle_failure "$marketplace_add" "$marketplace_status"; then
              claude_marketplace_degraded=1
              continue
            else
              return 1
            fi
          fi
        fi
      done < <("$claude_jq" -r --arg profile "$claude_profile_name" \
        '.[$profile].marketplaces // {} | to_entries[] | [.key, .value.repo] | @tsv' \
        "$claude_marketplaces")
      if [ "$claude_marketplace_degraded" -ne 0 ]; then
        return 0
      fi

      while IFS="$(printf '\t')" read -r plugin_name plugin_enabled; do
        [ -n "$plugin_name" ] || continue
        if plugin_list="$(${pkgs.claude-code}/bin/claude plugin list --json 2>&1)"; then
          :
        else
          plugin_status="$?"
          if claude_handle_failure "$plugin_list" "$plugin_status"; then
            continue
          else
            return 1
          fi
        fi
        if ! printf '%s\n' "$plugin_list" \
          | "$claude_jq" -e 'type == "array"' >/dev/null 2>&1; then
          echo "error: Claude plugin list returned invalid JSON: $plugin_list" >&2
          return 1
        fi
        if ! printf '%s\n' "$plugin_list" \
          | "$claude_jq" -e --arg plugin "$plugin_name" \
            'any(.[]; .id == $plugin)' >/dev/null 2>&1; then
          if plugin_install="$(${pkgs.claude-code}/bin/claude plugin install "$plugin_name" 2>&1)"; then
            :
          else
            plugin_status="$?"
            claude_handle_failure "$plugin_install" "$plugin_status" || return 1
            continue
          fi
        fi
        if plugin_enable="$(${pkgs.claude-code}/bin/claude plugin enable "$plugin_name" 2>&1)"; then
          :
        else
          plugin_status="$?"
          claude_handle_failure "$plugin_enable" "$plugin_status" || return 1
        fi
      done < <("$claude_jq" -r --arg profile "$claude_profile_name" \
        '.[$profile].plugins // {} | to_entries[] | [.key, (.value | tostring)] | @tsv' \
        "$claude_marketplaces")
    }

    run "$claude_jq" -e 'type == "object" and all(to_entries[]; .value | type == "string")' "$claude_environment" >/dev/null
    run "$claude_jq" -e 'type == "object" and (keys | sort) == ["gpt56", "mattpocock", "standard"] and all(to_entries[]; (.value | type) == "object" and ((.value.marketplaces | type) == "object") and all(.value.marketplaces | to_entries[]; .value.source == "github" and (.value.repo | type) == "string") and ((.value.plugins | type) == "object") and all(.value.plugins | to_entries[]; (.value | type) == "boolean"))' "$claude_marketplaces" >/dev/null
    ${lib.concatMapStringsSep "\n" (profile: ''
      claude_settings_dir="$HOME/${profile.configDir}"
      claude_settings="$claude_settings_dir/settings.json"
      run ${pkgs.coreutils}/bin/install -d -m 0700 "$claude_settings_dir"
      claude_bootstrap_profile=1
      claude_reconcile_profile=1
      if [ -e "$claude_settings" ]; then
        if [ ! -r "$claude_settings" ] || ! "$claude_jq" -e 'type == "object"' "$claude_settings" >/dev/null 2>&1; then
          claude_reconcile_profile=0
          echo "warning: leaving unreadable or malformed Claude settings untouched: $claude_settings" >&2
        else
          claude_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$claude_settings.XXXXXX")"
          if ! claude_reconcile "$claude_settings" "$claude_settings_tmp" \
            ${lib.escapeShellArg (toString profile.settings)} ${lib.escapeShellArg profile.name}; then
            ${pkgs.coreutils}/bin/rm -f "$claude_settings_tmp"
            echo "error: failed to reconcile Claude settings: $claude_settings" >&2
            exit 1
          fi
          run ${pkgs.coreutils}/bin/chmod 0600 "$claude_settings_tmp"
          run ${pkgs.coreutils}/bin/mv -f "$claude_settings_tmp" "$claude_settings"
        fi
      else
        claude_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$claude_settings.XXXXXX")"
        if ! claude_reconcile ${lib.escapeShellArg (toString profile.settings)} "$claude_settings_tmp" \
          ${lib.escapeShellArg (toString profile.settings)} ${lib.escapeShellArg profile.name}; then
          ${pkgs.coreutils}/bin/rm -f "$claude_settings_tmp"
          echo "error: failed to seed Claude settings: $claude_settings" >&2
          exit 1
        fi
        run ${pkgs.coreutils}/bin/chmod 0600 "$claude_settings_tmp"
        run ${pkgs.coreutils}/bin/mv -f "$claude_settings_tmp" "$claude_settings"
      fi
      if [ "$claude_bootstrap_profile" -eq 1 ]; then
        claude_bootstrap ${lib.escapeShellArg profile.name} ${lib.escapeShellArg profile.configDir}
      fi
      if [ "$claude_reconcile_profile" -eq 1 ]; then
        claude_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$claude_settings.XXXXXX")"
        if ! claude_reconcile "$claude_settings" "$claude_settings_tmp" \
          ${lib.escapeShellArg (toString profile.settings)} ${lib.escapeShellArg profile.name}; then
          ${pkgs.coreutils}/bin/rm -f "$claude_settings_tmp"
          echo "error: failed to finalize Claude settings: $claude_settings" >&2
          exit 1
        fi
        run ${pkgs.coreutils}/bin/chmod 0600 "$claude_settings_tmp"
        run ${pkgs.coreutils}/bin/mv -f "$claude_settings_tmp" "$claude_settings"
      fi
    '') claudeProfiles}
  '';

  home.activation.codexPolicy = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    codex_home="$HOME/.codex"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$codex_home"
    export CODEX_HOME="$codex_home"
    codex_legacy_last30days_skill="$codex_home/skills/last30days"
    if [ -L "$codex_legacy_last30days_skill" ] \
      && [ "$(${pkgs.coreutils}/bin/readlink "$codex_legacy_last30days_skill")" = "../../agents/skills/last30days" ]; then
      run ${pkgs.coreutils}/bin/rm -f "$codex_legacy_last30days_skill"
    fi
    codex_handle_failure() {
      codex_failure_output="$1"
      codex_failure_status="$2"
      if printf '%s\n' "$codex_failure_output" \
        | ${pkgs.gnugrep}/bin/grep -Eiq \
          'network|dns|resolve|github|remote|timed[ -]?out|timeout|connection|fetch|tls|temporar|unavailable|no such file|clone|premature|out[ -]?of[ -]?date|502|503|429'; then
        echo "warning: transient Codex marketplace failure (status $codex_failure_status); will retry on next activation: $codex_failure_output" >&2
        return 0
      fi
      echo "error: Codex marketplace/plugin command failed (status $codex_failure_status): $codex_failure_output" >&2
      return 1
    }

    codex_marketplace_degraded=0
    if codex_marketplaces="$(${pkgs.codex}/bin/codex plugin marketplace list 2>&1)"; then
      :
    else
      codex_status="$?"
      if codex_handle_failure "$codex_marketplaces" "$codex_status"; then
        codex_marketplace_degraded=1
        codex_marketplaces=""
      else
        exit "$codex_status"
      fi
    fi
    if [ "$codex_marketplace_degraded" -eq 0 ] \
      && ! printf '%s\n' "$codex_marketplaces" \
        | ${pkgs.gnugrep}/bin/grep -Eq '(^|[[:space:]])last30days-skill([[:space:]]|$)'; then
      if codex_marketplace_add="$(${pkgs.codex}/bin/codex plugin marketplace add mvanhorn/last30days-skill 2>&1)"; then
        :
      else
        codex_status="$?"
        if codex_handle_failure "$codex_marketplace_add" "$codex_status"; then
          codex_marketplace_degraded=1
        else
          exit "$codex_status"
        fi
      fi
    fi

    if [ "$codex_marketplace_degraded" -eq 0 ]; then
      if codex_plugins="$(${pkgs.codex}/bin/codex plugin list --json 2>&1)"; then
        :
      else
        codex_status="$?"
        if codex_handle_failure "$codex_plugins" "$codex_status"; then
          codex_marketplace_degraded=1
          codex_plugins=""
        else
          exit "$codex_status"
        fi
      fi
      if [ "$codex_marketplace_degraded" -eq 0 ] \
        && ! printf '%s\n' "$codex_plugins" \
          | ${pkgs.gnugrep}/bin/grep -Fq '"pluginId": "last30days@last30days-skill"'; then
        if codex_plugin_add="$(${pkgs.codex}/bin/codex plugin add last30days@last30days-skill 2>&1)"; then
          :
        else
          codex_status="$?"
          codex_handle_failure "$codex_plugin_add" "$codex_status" || exit "$codex_status"
        fi
      fi
    fi

    run ${pkgs.python3}/bin/python3 ${codexReconcile} \
      --base "$codex_home/config.toml"
    ${lib.concatMapStringsSep "\n" (name: ''
      run ${pkgs.python3}/bin/python3 ${codexReconcile} \
        --profile ${lib.escapeShellArg (toString ../../dotfiles/codex/profiles/${name}.config.toml)} \
        "$codex_home/${name}.config.toml"
    '') codexProfileNames}
  '';

  # pi rewrites ~/.pi/agent/settings.json at runtime (settings edits, model
  # switches), so it must be an ordinary mutable file rather than a link.
  # Same materialize-from-tracked-baseline treatment as Claude above.
  # auth.json stays machine-local and unmanaged.
  home.activation.piSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    pi_settings_dir="$HOME/.pi/agent"
    pi_settings="$pi_settings_dir/settings.json"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$pi_settings_dir"
    pi_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$pi_settings.XXXXXX")"

    run ${pkgs.coreutils}/bin/cp ${lib.escapeShellArg (toString ../../dotfiles/pi/settings.json)} "$pi_settings_tmp"

    run ${pkgs.coreutils}/bin/chmod 0600 "$pi_settings_tmp"
    run ${pkgs.coreutils}/bin/mv -f "$pi_settings_tmp" "$pi_settings"
  '';

  home.file = codexSkillLinks // {
    # Codex CLI authored resources. The base config.toml, profiles, auth,
    # sessions, caches, marketplaces, and installed payloads stay mutable.
    ".codex/AGENTS.md".source = link "dotfiles/codex/AGENTS.md";
    ".codex/rules/default.rules".source = link "dotfiles/codex/rules/default.rules";

    # Curated agent skill pool, shared with Codex profiles via relative
    # shared-skills/<name> paths. Force because a manually created bridge
    # symlink will already exist at activation time.
    ".codex/shared-skills" = {
      source = link "dotfiles/agents/skills";
      force = true;
    };
  };

  xdg.configFile = {
    # fcitx5 — global config, input-method profile, and per-addon conf/.
    # conf/cached_layouts regenerates here and is git-ignored; the learned
    # pinyin dictionary lives under ~/.local/share/fcitx5 and is untouched.
    "fcitx5".source = link "dotfiles/fcitx5";

    # Claude Code (CLAUDE_CONFIG_DIR=~/.config/claude) — stable authored config.
    "claude/CLAUDE.md".source = link "dotfiles/claude/CLAUDE.md";
    "claude/statusline.sh".source = link "dotfiles/claude/statusline.sh";
    "claude/skills/nix-environment-setup".source = link "dotfiles/claude/skills/nix-environment-setup";
    "claude/skills/agent-config-setup".source = link "dotfiles/claude/skills/agent-config-setup";
    "claude/skills/bro".source = link "dotfiles/claude/skills/bro";
    "claude/skills/visual-verification".source = link "dotfiles/claude/skills/visual-verification";
    "claude/skills/domain-context".source = link "dotfiles/claude/skills/domain-context";
    "claude/skills/lavish".source = link "dotfiles/claude/skills/lavish";
    "claude/skills/r-dev-shell".source = link "dotfiles/claude/skills/r-dev-shell";
    "claude/commands".source = link "dotfiles/claude/commands";
    "claude/output-styles".source = link "dotfiles/claude/output-styles";
    "claude/agents".source = link "dotfiles/claude/agents";

    # GPT-5.6 gateway profile. Share portable authored assets from the standard
    # profile, but keep credentials, history, sessions, plugins, caches, and all
    # other mutable state isolated under its own CLAUDE_CONFIG_DIR.
    "claude-gpt56/CLAUDE.md".source = link "dotfiles/claude-gpt56/CLAUDE.md";
    "claude-gpt56/statusline.sh".source = link "dotfiles/claude/statusline.sh";
    "claude-gpt56/commands".source = link "dotfiles/claude/commands";
    "claude-gpt56/output-styles".source = link "dotfiles/claude/output-styles";
    "claude-gpt56/agents".source = link "dotfiles/claude/agents";
    "claude-gpt56/skills/bro".source = link "dotfiles/claude/skills/bro";
    "claude-gpt56/skills/agent-config-setup".source = link "dotfiles/claude/skills/agent-config-setup";
    "claude-gpt56/skills/nix-environment-setup".source =
      link "dotfiles/claude/skills/nix-environment-setup";
    "claude-gpt56/skills/visual-verification".source =
      link "dotfiles/claude/skills/visual-verification";
    "claude-gpt56/skills/domain-context".source = link "dotfiles/claude/skills/domain-context";
    "claude-gpt56/skills/lavish".source = link "dotfiles/claude/skills/lavish";
    "claude-gpt56/skills/r-dev-shell".source = link "dotfiles/claude/skills/r-dev-shell";

    # Claude has a profile per CLAUDE_CONFIG_DIR. Share only portable authored
    # assets with claude-mattpocock; its credential, settings, plugin state,
    # history, and independently managed Matt Pocock skill set stay mutable.
    "claude-mattpocock/CLAUDE.md" = {
      source = link "dotfiles/claude/CLAUDE.md";
      force = true;
    };
    "claude-mattpocock/statusline.sh" = {
      source = link "dotfiles/claude/statusline.sh";
      force = true;
    };
    "claude-mattpocock/commands" = {
      source = link "dotfiles/claude/commands";
      force = true;
    };
    "claude-mattpocock/output-styles" = {
      source = link "dotfiles/claude/output-styles";
      force = true;
    };
    "claude-mattpocock/agents" = {
      source = link "dotfiles/claude/agents";
      force = true;
    };
    "claude-mattpocock/skills/nix-environment-setup" = {
      source = link "dotfiles/claude/skills/nix-environment-setup";
      force = true;
    };
    "claude-mattpocock/skills/agent-config-setup" = {
      source = link "dotfiles/claude/skills/agent-config-setup";
      force = true;
    };
    "claude-mattpocock/skills/visual-verification" = {
      source = link "skills/visual-verification";
      force = true;
    };
    "claude-mattpocock/skills/bro" = {
      source = link "dotfiles/claude/skills/bro";
      force = true;
    };
    "claude-mattpocock/skills/domain-context" = {
      source = link "dotfiles/claude/skills/domain-context";
      force = true;
    };
    "claude-mattpocock/skills/lavish" = {
      source = link "dotfiles/claude/skills/lavish";
      force = true;
    };
    "claude-mattpocock/skills/r-dev-shell" = {
      source = link "dotfiles/claude/skills/r-dev-shell";
      force = true;
    };
  };
}
