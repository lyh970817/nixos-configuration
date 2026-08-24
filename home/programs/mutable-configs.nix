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
  # The theme is the custom dark theme below in dark mode and stock light-ansi
  # in light, chosen from this machine's current mode at activation below and
  # rewritten on a mode switch by claude-theme (desktop/theming.nix).
  link = subpath: config.lib.file.mkOutOfStoreSymlink "${osConfig.portable.configDir}/${subpath}";
  # Every tracked file read below at activation time is snapshotted through
  # writeText and interpolated as a derivation, never as `toString path`. A
  # bare toString yields the store path as a plain string carrying no string
  # context, so Nix records no reference to it: the path is baked into the
  # activation script while the flake source snapshot it points into stays
  # unreachable, and the next garbage collection deletes the file out from
  # under a script that still names it. The failure is silent and delayed.
  claudeEnvironment = pkgs.writeText "claude-environment.json" (
    builtins.readFile ../../dotfiles/claude/environment.json
  );
  claudeMarketplaces = pkgs.writeText "claude-marketplaces.json" (
    builtins.readFile ../../dotfiles/claude/marketplaces.json
  );
  claudeHerdrSessionHook = "${config.home.homeDirectory}/.config/claude/hooks/herdr-agent-state.sh";
  claudeHerdrSessionCommand = "bash '${
    lib.replaceStrings [ "'" ] [ "'\\''" ] claudeHerdrSessionHook
  }' session";
  # Silent per-pane session registration for scripts/herdr-explain-current;
  # linked into each launcher-backed profile's hooks/ below, so the command
  # path is per profile.
  claudeExplainRegisterCommand =
    configDir:
    "bash '${
      lib.replaceStrings [ "'" ] [ "'\\''" ]
        "${config.home.homeDirectory}/${configDir}/hooks/explain-session-register.sh"
    }'";
  claudeProfiles = [
    {
      name = "standard";
      configDir = ".config/claude";
      settings = pkgs.writeText "claude-settings-standard.json" (
        builtins.readFile ../../dotfiles/claude/settings.json
      );
    }
    {
      name = "mattpocock";
      configDir = ".config/claude-mattpocock";
      settings = pkgs.writeText "claude-settings-mattpocock.json" (
        builtins.readFile ../../dotfiles/claude-mattpocock/settings.json
      );
    }
    {
      name = "gpt56";
      configDir = ".config/claude-gpt56";
      settings = pkgs.writeText "claude-settings-gpt56.json" (
        builtins.readFile ../../dotfiles/claude-gpt56/settings.json
      );
    }
  ];

  # Claude Code custom theme, installed into every profile above.
  #
  # dark-ansi fills three slabs -- the user message row, the composer sidebar,
  # and the memory banner -- with ANSI bright black as a *background*. Its
  # syntax map, which is hardcoded and reads no theme key, draws comments and
  # `meta` on that same slot as a *foreground*. One rung cannot serve both:
  # near the background the slabs are right and comments are invisible, high
  # enough to read comments and the slabs glow. This theme repoints the three
  # slabs at palette index 236, which foot.nix pins to
  # subtleBorder, so they render exactly as before while bright black is freed
  # to carry mutedText. Both halves are required; either alone is a regression.
  #
  # Only keys already present in `base` are honoured and unknown ones are
  # dropped in silence. A slug that does not resolve is worse: the theme falls
  # back to 24-bit "dark" with no error, so the file name here and the `theme`
  # value written by the three writers (this file, programs/claude.nix, and
  # claude-theme in desktop/theming.nix) must agree exactly. Claude Code only
  # writes this directory from its own theme editor, so a read-only link is
  # safe; the directory itself stays writable for themes saved that way.
  #
  # Light mode keeps stock light-ansi: there those three keys are ansi:white,
  # not bright black, so nothing needs rerouting.
  claudeThemeSlug = "phosphor-dark";
  claudeTheme = pkgs.writeText "${claudeThemeSlug}.json" (
    builtins.toJSON {
      name = "Phosphor dark";
      base = "dark-ansi";
      overrides = {
        userMessageBackground = "ansi256(236)";
        composerSidebarBackground = "ansi256(236)";
        memoryBackgroundColor = "ansi256(236)";
      };
    }
  );
  claudeThemeFiles = lib.listToAttrs (
    map (profile: {
      name = "${lib.removePrefix ".config/" profile.configDir}/themes/${claudeThemeSlug}.json";
      value.source = claudeTheme;
    }) claudeProfiles
  );

  codexProfileNames = [
    "last30days"
    "mattpocock"
    "orchestrator"
    "superpowers"
    "understand-anything-codegraph"
  ];

  codexProfileConfigs = lib.listToAttrs (
    map (name: {
      inherit name;
      value = pkgs.writeText "codex-${name}.config.toml" (
        builtins.readFile ../../dotfiles/codex/profiles/${name}.config.toml
      );
    }) codexProfileNames
  );

  codexAgentNames = [ "merge" ];

  codexAgentFiles = lib.listToAttrs (
    map (name: {
      inherit name;
      value = pkgs.writeText "codex-agent-${name}.toml" (
        builtins.readFile ../../dotfiles/codex/agents/${name}.toml
      );
    }) codexAgentNames
  );

  codexSkillNames = [
    "nix-environment-setup"
    "bro"
    "commit-guidelines"
    "domain-context"
    "herdr"
    "r-dev-shell"
    "session-handoff"
    "social-bookmarks"
    "tuicr"
    "visual-verification"
    "writing-agent-instructions"
  ];

  codexSkillLinks = lib.listToAttrs (
    (map (name: {
      name = ".codex/skills/${name}";
      value = {
        source = link "dotfiles/codex/skills/${name}";
        force = true;
      };
    }) codexSkillNames)
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
    ASSIGNMENT = re.compile(
        r"^\s*(?:[A-Za-z0-9_-]+|\"(?:[^\"\\]|\\.)*\"|'[^']*')\s*="
    )
    DISABLED_PLUGINS = [
        "browser@openai-bundled",
        "computer-use@openai-bundled",
        "sites@openai-bundled",
        "visualize@openai-bundled",
        "deep-research@openai-bundled",
    ]
    ENABLED_PLUGINS = [
        "chrome@openai-bundled",
    ]
    # Curated remote skills remain blocked even if a future CLI release ignores
    # remote_plugin for an already-cached plugin.  These names come from the
    # manifests currently shipped by openai-templates, not its plugin name.
    OPENAI_TEMPLATE_SKILLS = [
        "openai-templates:artifact-template-analytics-dashboard",
        "openai-templates:artifact-template-business-review",
        "openai-templates:artifact-template-design-report",
        "openai-templates:artifact-template-experiment-analysis",
        "openai-templates:artifact-template-financial-budget",
        "openai-templates:artifact-template-investment-committee-memo",
        "openai-templates:artifact-template-legal-memorandum",
        "openai-templates:artifact-template-market-trends-report",
        "openai-templates:artifact-template-minimal-letterhead",
        "openai-templates:artifact-template-operating-calendar",
        "openai-templates:artifact-template-operating-review",
        "openai-templates:artifact-template-project-kickoff",
        "openai-templates:artifact-template-project-tracker",
        "openai-templates:artifact-template-sales-pipeline",
        "openai-templates:artifact-template-simple-dark-mode",
        "openai-templates:artifact-template-simple-light-mode",
        "openai-templates:artifact-template-strategy-memorandum",
        "openai-templates:artifact-template-system-design",
        "openai-templates:artifact-template-team-alignment",
        "openai-templates:artifact-template-three-statement-forecast",
    ]
    DISABLED_SKILLS = [
        "build-iso",
        "kcl-fetch",
        "last30days:last30days",
        "imagegen",
        "plugin-creator",
        "control-in-app-browser",
        "visualize",
        "sites-hosting",
        "sites-building",
        "deep-research",
        "google-drive",
        "google-drive:google-drive",
        "google-drive:google-drive-comments",
        "google-drive:google-docs",
        "google-drive:google-sheets",
        "google-drive:google-slides",
    ] + OPENAI_TEMPLATE_SKILLS
    # These are explicit enables, rather than relying on Codex's default, so
    # an older mutable config cannot keep a required bundled skill hidden.
    ENABLED_SKILLS = [
        "control-chrome",
        "openai-docs",
        "skill-creator",
        "skill-installer",
    ]
    # Older activations could write either the runtime system-skill path or
    # this checkout's legacy path.  Recognize only those exact roots: a user
    # path which merely happens to contain one of these names stays user-owned.
    ENABLED_SYSTEM_SKILL_PATHS = {
        os.path.normpath(os.path.join(root, skill, "SKILL.md")): skill
        for root in (
            os.path.expanduser("~/.codex/skills/.system"),
            "${osConfig.portable.configDir}/dotfiles/codex/skills/.system",
        )
        for skill in ENABLED_SKILLS
    }
    PATH_SKILLS = {
        "build-iso": "build-iso",
        "kcl-fetch": "kcl-fetch",
        "last30days": "last30days:last30days",
        "control-chrome": "control-chrome",
        "control-in-app-browser": "control-in-app-browser",
        "sites-hosting": "sites-hosting",
        "sites-building": "sites-building",
        "deep-research": "deep-research",
        "google-drive": "google-drive",
    } | {
        skill.removeprefix("openai-templates:"): skill
        for skill in OPENAI_TEMPLATE_SKILLS
    }
    # Remove only these known stale selectors from persisted configuration.
    OBSOLETE_PROFILE_SKILLS = {
        "mattpocock": {
            "ask-matt",
            "code-review",
            "codebase-design",
            "diagnosing-bugs",
            "grill-me",
            "grill-with-docs",
            "grilling",
            "handoff",
            "implement",
            "improve-codebase-architecture",
            "loop-me",
            "prototype",
            "research",
            "resolving-merge-conflicts",
            "setup-matt-pocock-skills",
            "setup-pre-commit",
            "tdd",
            "to-spec",
            "to-tickets",
            "triage",
            "wayfinder",
            "wizard",
            "writing-great-skills",
        },
        "superpowers": {
            "codex-dynamic-workflows",
            "superpowers-domain-context",
        },
    }
    OBSOLETE_BASE_SKILL_NAMES = set().union(*OBSOLETE_PROFILE_SKILLS.values())
    OBSOLETE_BASE_SKILL_PATHS = {
        os.path.expanduser("~/.codex/skills/superpowers-domain-context/SKILL.md"),
    }

    def value(item):
        return json.dumps(item, separators=(",", ":"))

    def assignment_end(lines, index, limit):
        line = lines[index]
        if not ASSIGNMENT.match(line):
            return index + 1
        rendered = line.split("=", 1)[1].lstrip()
        delimiter = next(
            (candidate for candidate in ('"""', "'" * 3) if rendered.startswith(candidate)),
            None,
        )
        if delimiter is None:
            return index + 1
        fragments = [rendered[len(delimiter):]] + lines[index + 1:limit]
        for offset, fragment in enumerate(fragments):
            cursor = 0
            while True:
                closing = fragment.find(delimiter, cursor)
                if closing < 0:
                    break
                if delimiter == "'" * 3:
                    return index + offset + 1
                backslashes = 0
                before = closing - 1
                while before >= 0 and fragment[before] == "\\":
                    backslashes += 1
                    before -= 1
                if backslashes % 2 == 0:
                    return index + offset + 1
                cursor = closing + 1
        return index + 1

    def headers(lines):
        index = 0
        while index < len(lines):
            line = lines[index]
            match = HEADER.match(line.rstrip("\n"))
            if match:
                yield index, match.group(1), match.group(2).strip()
            end = assignment_end(lines, index, len(lines))
            index = end if end > index + 1 else index + 1

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
            index = 0
            header_index = next((header for header, _, _ in headers(lines)), len(lines))
            while index < header_index:
                line = lines[index]
                if HEADER.match(line.rstrip("\n")):
                    break
                if pattern.match(line):
                    replacement = "%s = %s\n" % (key, rendered)
                    end = assignment_end(lines, index, len(lines))
                    if lines[index:end] == [replacement]:
                        return False
                    lines[index:end] = [replacement]
                    return True
                end = assignment_end(lines, index, header_index)
                index = end if end > index + 1 else index + 1
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
        index = start + 1
        while index < end:
            if pattern.match(lines[index]):
                replacement = "%s = %s\n" % (key, rendered)
                assignment_stop = assignment_end(lines, index, len(lines))
                if lines[index:assignment_stop] == [replacement]:
                    return False
                lines[index:assignment_stop] = [replacement]
                return True
            assignment_stop = assignment_end(lines, index, end)
            index = assignment_stop if assignment_stop > index + 1 else index + 1
        lines.insert(start + 1, "%s = %s\n" % (key, rendered))
        return True

    def remove_map_key(lines, table, key, case_insensitive=False):
        table_index = next(
            (
                index
                for index, opening, name in headers(lines)
                if opening == "[" and name == table
            ),
            None,
        )
        if table_index is None:
            return False
        start, end = bounds(lines, table_index)
        matches = []
        index = start + 1
        while index < end:
            stop = assignment_end(lines, index, end)
            if ASSIGNMENT.match(lines[index]):
                left = lines[index].split("=", 1)[0].strip()
                try:
                    parsed = tomllib.loads("%s = 0" % left)
                except tomllib.TOMLDecodeError:
                    parsed = {}
                if len(parsed) == 1:
                    existing = next(iter(parsed))
                    matched = existing == key
                    if case_insensitive:
                        matched = existing.casefold() == key.casefold()
                    if matched:
                        matches.append((index, stop))
            index = stop if stop > index + 1 else index + 1
        if not matches:
            return False
        for match_start, match_stop in reversed(matches):
            del lines[match_start:match_stop]
        _, end = bounds(lines, table_index)
        if all(not line.strip() for line in lines[table_index + 1:end]):
            del lines[table_index:end]
        return True

    def skill_blocks(lines):
        for index, opening, name in headers(lines):
            if opening == "[[" and name == "skills.config":
                yield bounds(lines, index)

    def quoted_field(lines, start, end, field):
        pattern = re.compile(r"^\s*%s\s*=\s*([\"'])(.*?)\1" % field)
        index = start + 1
        while index < end:
            match = pattern.match(lines[index])
            if match:
                return index, match.group(2)
            assignment_stop = assignment_end(lines, index, end)
            index = assignment_stop if assignment_stop > index + 1 else index + 1
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

    def atomic_write(path, content, requested_mode=None):
        directory = os.path.dirname(path) or "."
        os.makedirs(directory, mode=0o700, exist_ok=True)
        mode = requested_mode
        if mode is None:
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
        # Pin the syntax theme at the one generated from the phosphor palette
        # (see programs/codex-theme.nix). Every bundled bat theme hardcodes its
        # own RGB, so a stray /theme silently strands code blocks and the
        # status line on a scheme that fights the rest of the terminal.
        changed = table_key(lines, "tui", "theme", '"vt220-phosphor"') or changed
        changed = table_key(
            lines, "tui.keymap.global", "open_transcript", '"ctrl-o"'
        ) or changed
        changed = table_key(lines, "tui.keymap.global", "copy", '"f12"') or changed
        changed = remove_map_key(
            lines,
            "shell_environment_policy.filters",
            "NO_COLOR",
            case_insensitive=True,
        ) or changed
        for plugin in DISABLED_PLUGINS:
            changed = table_key(lines, 'plugins."%s"' % plugin, "enabled", "false") or changed
        for plugin in ENABLED_PLUGINS:
            changed = table_key(lines, 'plugins."%s"' % plugin, "enabled", "true") or changed
        present = set()
        for start, end in reversed(list(skill_blocks(lines))):
            name_index, name = quoted_field(lines, start, end, "name")
            path_index, skill_path = quoted_field(lines, start, end, "path")
            # Before template manifests had individual selectors, the generic
            # plugin name was written here. It cannot disable any manifest and
            # is the sole stale skill block we remove; every other unknown
            # user-owned block stays untouched.
            if name == "openai-templates":
                del lines[start:end]
                changed = True
                continue
            if name in OBSOLETE_BASE_SKILL_NAMES or skill_path in OBSOLETE_BASE_SKILL_PATHS:
                del lines[start:end]
                changed = True
                continue
            selected = name if name in DISABLED_SKILLS or name in ENABLED_SKILLS else None
            if selected is None and skill_path:
                selected = ENABLED_SYSTEM_SKILL_PATHS.get(
                    os.path.normpath(os.path.expanduser(skill_path))
                )
            if selected is None and skill_path:
                for marker, stable in PATH_SKILLS.items():
                    if "/" + marker + "/" in skill_path or skill_path.endswith("/" + marker + "/SKILL.md"):
                        selected = stable
                        break
            if selected is None:
                continue
            if selected in present:
                del lines[start:end]
                changed = True
                continue
            present.add(selected)
            if path_index is not None:
                lines[path_index] = 'name = "%s"\n' % selected
                changed = True
            changed = set_enabled(lines, start, end, selected in ENABLED_SKILLS) or changed
        for skill in DISABLED_SKILLS:
            if skill not in present:
                append_block(lines, [
                    "[[skills.config]]",
                    'name = "%s"' % skill,
                    "enabled = false",
                ])
                changed = True
        for skill in ENABLED_SKILLS:
            if skill not in present:
                append_block(lines, [
                    "[[skills.config]]",
                    'name = "%s"' % skill,
                    "enabled = true",
                ])
                changed = True
        new = "".join(lines)
        if changed and new != old:
            try:
                tomllib.loads(new)
            except tomllib.TOMLDecodeError as error:
                raise SystemExit("Codex policy reconciliation produced invalid TOML: %s" % error)
            atomic_write(path, new)

    def reconcile_profile(profile_name, template_path, path):
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
            atomic_write(path, policy_text, 0o600)
            return
        lines = old.splitlines(True)
        changed = False
        for key in (
            "model",
            "model_reasoning_effort",
            "include_collaboration_mode_instructions",
            "developer_instructions",
        ):
            if key in policy:
                changed = table_key(lines, "", key, value(policy[key])) or changed
        multi_agent_policy = policy.get("features", {}).get("multi_agent_v2", {})
        for key in (
            "enabled",
            "max_concurrent_threads_per_session",
            "expose_spawn_agent_model_overrides",
            "multi_agent_mode_hint_text",
            "subagent_developer_instructions",
        ):
            if key in multi_agent_policy:
                changed = table_key(
                    lines,
                    "features.multi_agent_v2",
                    key,
                    value(multi_agent_policy[key]),
                ) or changed
        for plugin, settings in policy.get("plugins", {}).items():
            for key, setting in settings.items():
                changed = table_key(lines, 'plugins."%s"' % plugin, key, value(setting)) or changed
        for server, settings in policy.get("mcp_servers", {}).items():
            for key, setting in settings.items():
                changed = table_key(lines, "mcp_servers.%s" % server, key, value(setting)) or changed
        desired = policy.get("skills", {}).get("config", [])
        desired_names = {entry.get("name") for entry in desired}
        obsolete_names = OBSOLETE_PROFILE_SKILLS.get(profile_name, set())
        existing = set()
        for start, end in reversed(list(skill_blocks(lines))):
            _, name = quoted_field(lines, start, end, "name")
            if name in obsolete_names:
                del lines[start:end]
                changed = True
                continue
            if name == "last30days" and name not in desired_names:
                del lines[start:end]
                changed = True
                continue
            if name is None:
                continue
            for entry in desired:
                if entry.get("name") == name:
                    existing.add(name)
                    if "enabled" in entry:
                        changed = set_enabled(lines, start, end, bool(entry["enabled"])) or changed
                    break
        for entry in desired:
            if entry.get("name") not in existing:
                append_block(lines, [
                    "[[skills.config]]",
                    'name = "%s"' % entry["name"],
                    "enabled = %s" % ("true" if entry.get("enabled") else "false"),
                ])
                changed = True
        new = "".join(lines)
        if (changed and new != old) or os.path.islink(path):
            tomllib.loads(new)
            atomic_write(path, new, 0o600)
        elif stat.S_IMODE(os.stat(path).st_mode) != 0o600:
            os.chmod(path, 0o600)

    parser = argparse.ArgumentParser()
    parser.add_argument("--base")
    parser.add_argument("--profile", nargs=3, action="append", default=[])
    args = parser.parse_args()
    if args.base:
        reconcile_base(args.base)
    for profile, template, target in args.profile:
        reconcile_profile(profile, template, target)
  '';

  piSettings = pkgs.writeText "pi-settings.json" (builtins.readFile ../../dotfiles/pi/settings.json);
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
  home.activation.removeLegacyAgentDirectoryLinks = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    for legacy_link in \
      "$HOME/.codex/rules" \
      "$HOME/.codex/skills" \
      "$HOME/.config/claude/skills"; do
      if [ -L "$legacy_link" ]; then
        run ${pkgs.coreutils}/bin/rm -f "$legacy_link"
      fi
    done
  '';

  # Presentation and policy keys written into every profile's settings.json.
  #
  # These are a *machine-mode fallback*, not the usual path. The launcher in
  # programs/claude.nix themes each session from THEME_MODE and passes it as
  # --settings, which lands in flagSettings and outranks settings.json. Its
  # CLAUDE_CODE_PROCESS_WRAPPER does the same for Claude's agent-view,
  # background, and other self-execs while preserving the inherited session
  # mode. Only a truly direct, unwrapped binary launch reads this fallback.
  #
  # Written per mode rather than pinned, so the fallback is also right in light
  # mode. dark-ansi and light-ansi are the only two themes drawn purely from
  # ANSI slots, and so the only ones that follow the phosphor ladder and the
  # e-ink palette respectively. `auto` is not the answer despite its "match
  # terminal" label: it only chooses between the two 24-bit themes, and both
  # ignore the terminal palette. Dark mode names the custom theme above rather
  # than dark-ansi itself; it is dark-ansi with three slab backgrounds moved
  # off bright black, and it keeps the ANSI syntax map because that is keyed on
  # the custom theme's `base`.
  #
  # prefersReducedMotion is the same story. The spinner's effort suffix is
  # drawn in a hardcoded RGB grey that no theme key reaches; reduced motion
  # selects the branch that colours it from the theme instead.
  #
  # tui pins the fullscreen renderer. Claude Code ships two; the classic one
  # never mounts the scroll hook or the virtual scrollbox, so every scroll key
  # in Ctrl+O transcript mode (k/j/Ctrl+U/Ctrl+B/g/G/arrows/PgUp/PgDn) has no
  # handler registered at all, while Ctrl+E/q/Escape still work. Left unset the
  # renderer falls to per-session experiment flags, which is why scrolling
  # "sometimes" worked. Chosen over CLAUDE_CODE_NO_FLICKER=1 in the launcher so
  # /tui default stays usable per session. Written here rather than in a
  # profile template because it is not per-profile and because a template key
  # with no stage in claude_reconcile below is silently dropped -- exactly how
  # this setting was lost once already.
  #
  # editorMode and includeCoAuthoredBy are user and repo policy rather than
  # presentation, but they are pinned here for the same reason: both were lost
  # to that template rewrite too, and neither varies by profile. Vim keys are
  # wanted everywhere (Codex profiles already enable them), and the no-trailer
  # rule in CLAUDE.md applies to every profile committing to this repo, so
  # tying them to one template would only reintroduce the drift. Note
  # includeCoAuthoredBy is false, so any stage guarding it must test the type
  # rather than the value -- a bare truthiness test drops it exactly like a
  # missing key. These are unconditional assignments for that reason.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    claude_jq=${pkgs.jq}/bin/jq
    claude_environment=${lib.escapeShellArg "${claudeEnvironment}"}
    claude_marketplaces=${lib.escapeShellArg "${claudeMarketplaces}"}
    claude_herdr_session_command=${lib.escapeShellArg claudeHerdrSessionCommand}
    claude_explain_register_standard=${lib.escapeShellArg (claudeExplainRegisterCommand ".config/claude")}
    claude_explain_register_gpt56=${lib.escapeShellArg (claudeExplainRegisterCommand ".config/claude-gpt56")}

    # Which ANSI-only theme matches this machine's current mode. Derived from
    # the hypr current-theme symlink, the same source the claude-theme helper
    # in desktop/theming.nix uses when a mode switch rewrites the same key --
    # so the two writers cannot disagree. Defaults to dark when the link is
    # missing, matching the btop and nmtui wrappers.
    case "$(readlink "$HOME/.local/state/hypr/current-theme.lua" 2>/dev/null)" in
      *light.lua) claude_theme="light-ansi" ;;
      *) claude_theme="custom:${claudeThemeSlug}" ;;
    esac

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
        --arg claude_theme "$claude_theme" \
        --arg claude_herdr_session_command "$claude_herdr_session_command" \
        --arg claude_explain_register_standard "$claude_explain_register_standard" \
        --arg claude_explain_register_gpt56 "$claude_explain_register_gpt56" \
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
            # Fallback presentation for sessions the launcher never sees.
            # Rationale above the activation block; keep apostrophes out of
            # this jq program, it is inside a single-quoted shell string.
            .theme = $claude_theme |
            .prefersReducedMotion = true |
            .tui = "fullscreen" |
            .editorMode = "vim" |
            .includeCoAuthoredBy = false |
            (if ($template.hooks | type) == "object" then .hooks = $template.hooks else . end) |
            if $profile == "standard" then
              .hooks.SessionStart = [{
                matcher: "*",
                hooks: [{
                  type: "command",
                  command: $claude_herdr_session_command,
                  timeout: 10
                }, {
                  type: "command",
                  command: $claude_explain_register_standard,
                  timeout: 10
                }]
              }]
            elif $profile == "gpt56" then
              .hooks.SessionStart = [{
                matcher: "*",
                hooks: [{
                  type: "command",
                  command: $claude_explain_register_gpt56,
                  timeout: 10
                }]
              }]
            else .
            end |
            # Same guard as hooks: only profiles whose template declares the
            # key get it, so the others are not handed a null.
            (if ($template.worktree | type) == "object" then .worktree = $template.worktree else . end) |
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
        ' "$input" > "$output" &&
        { [ "$profile_name" != "standard" ] ||
          "$claude_jq" -e --arg expected "$claude_herdr_session_command" \
            --arg register "$claude_explain_register_standard" \
            '.hooks.SessionStart[0].hooks[0].command == $expected
             and .hooks.SessionStart[0].hooks[1].command == $register' \
            "$output" >/dev/null; }
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
            ${lib.escapeShellArg "${profile.settings}"} ${lib.escapeShellArg profile.name}; then
            ${pkgs.coreutils}/bin/rm -f "$claude_settings_tmp"
            echo "error: failed to reconcile Claude settings: $claude_settings" >&2
            exit 1
          fi
          run ${pkgs.coreutils}/bin/chmod 0600 "$claude_settings_tmp"
          run ${pkgs.coreutils}/bin/mv -f "$claude_settings_tmp" "$claude_settings"
        fi
      else
        claude_settings_tmp="$(${pkgs.coreutils}/bin/mktemp "$claude_settings.XXXXXX")"
        if ! claude_reconcile ${lib.escapeShellArg "${profile.settings}"} "$claude_settings_tmp" \
          ${lib.escapeShellArg "${profile.settings}"} ${lib.escapeShellArg profile.name}; then
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
          ${lib.escapeShellArg "${profile.settings}"} ${lib.escapeShellArg profile.name}; then
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
        --profile ${lib.escapeShellArg name} ${lib.escapeShellArg "${codexProfileConfigs.${name}}"} \
        "$codex_home/${name}.config.toml"
    '') codexProfileNames}
  '';

  # Codex opens custom-agent definitions through its sensitive-file reader,
  # which rejects a symlink at the final path component. Keep the tracked
  # definitions authoritative, but install regular private files atomically.
  home.activation.codexAgents = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    codex_agents_dir="$HOME/.codex/agents"
    run ${pkgs.coreutils}/bin/install -d -m 0700 "$codex_agents_dir"
    ${lib.concatMapStringsSep "\n" (name: ''
      codex_agent="$codex_agents_dir/${name}.toml"
      codex_agent_tmp="$(${pkgs.coreutils}/bin/mktemp "$codex_agent.XXXXXX")"

      run ${pkgs.coreutils}/bin/cp \
        ${lib.escapeShellArg "${codexAgentFiles.${name}}"} \
        "$codex_agent_tmp"
      run ${pkgs.coreutils}/bin/chmod 0600 "$codex_agent_tmp"
      run ${pkgs.coreutils}/bin/mv -f "$codex_agent_tmp" "$codex_agent"
    '') codexAgentNames}
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

    run ${pkgs.coreutils}/bin/cp ${lib.escapeShellArg "${piSettings}"} "$pi_settings_tmp"

    run ${pkgs.coreutils}/bin/chmod 0600 "$pi_settings_tmp"
    run ${pkgs.coreutils}/bin/mv -f "$pi_settings_tmp" "$pi_settings"
  '';

  home.file = codexSkillLinks // {
    # Codex CLI authored resources. The base config.toml, profiles, auth,
    # sessions, caches, marketplaces, and installed payloads stay mutable.
    ".codex/AGENTS.md".source = link "dotfiles/codex/AGENTS.md";
    ".codex/hooks.json" = {
      source = link "dotfiles/codex/hooks.json";
      force = true;
    };
    ".codex/hooks/response-simplifier.sh".source = link "dotfiles/codex/hooks/response-simplifier.sh";
    # The two rewrite prompts were tuned against different models and no longer
    # share a source: the Claude one is cut for `claude-sonnet-5`, this one is
    # the preservation-first text validated against `gpt-5.6-luna` in
    # docs/stop-hook-model-comparison.md.
    ".codex/response-simplifier.md".source = link "dotfiles/codex/response-simplifier.md";
    ".codex/rules/default.rules".source = link "dotfiles/codex/rules/default.rules";
  };

  # The custom theme, read-only in every profile's themes/ directory.
  xdg.configFile = claudeThemeFiles // {
    # fcitx5 — global config, input-method profile, and per-addon conf/.
    # conf/cached_layouts regenerates here and is git-ignored; the learned
    # pinyin dictionary lives under ~/.local/share/fcitx5 and is untouched.
    "fcitx5".source = link "dotfiles/fcitx5";

    # Claude Code (CLAUDE_CONFIG_DIR=~/.config/claude) — stable authored config.
    "claude/CLAUDE.md".source = link "dotfiles/claude/CLAUDE.md";
    "claude/statusline.sh".source = link "dotfiles/claude/statusline.sh";
    "claude/hooks/response-simplifier.sh".source = link "dotfiles/claude/hooks/response-simplifier.sh";
    # Orchestrator system prompts, passed by the `clo` alias and by the
    # session-handoff skill with --append-system-prompt-file.
    "claude/orchestrator-opus.md".source = link "dotfiles/claude/orchestrator-opus.md";
    "claude/orchestrator-fable.md".source = link "dotfiles/claude/orchestrator-fable.md";
    # Rewrite prompt for the MessageDisplay hook above, passed with
    # --system-prompt-file.
    "claude/response-simplifier.md".source = link "dotfiles/claude/response-simplifier.md";
    "claude/skills/session-handoff".source = link "dotfiles/claude/skills/session-handoff";
    "claude/skills/explain-session".source = link "dotfiles/claude/skills/explain-session";
    "claude/skills/explain-session-sync".source = link "dotfiles/claude/skills/explain-session-sync";
    # Prompt templates read by explainctl (pkgs/explainctl) at fork/resume
    # time; linked per launcher-backed profile so the recorded launcher finds
    # its own copy.
    "claude/explain-session".source = link "dotfiles/claude/explain-session";
    "claude/hooks/explain-session-register.sh".source =
      link "dotfiles/claude/hooks/explain-session-register.sh";
    "claude/skills/nix-environment-setup".source = link "dotfiles/claude/skills/nix-environment-setup";
    "claude/skills/bro".source = link "dotfiles/claude/skills/bro";
    "claude/skills/visual-verification".source = link "dotfiles/claude/skills/visual-verification";
    "claude/skills/domain-context".source = link "dotfiles/claude/skills/domain-context";
    "claude/skills/domain-modeling".source = link "dotfiles/claude/skills/domain-modeling";
    "claude/skills/herdr".source = link "dotfiles/claude/skills/herdr";
    "claude/skills/r-dev-shell".source = link "dotfiles/claude/skills/r-dev-shell";
    "claude/skills/social-bookmarks".source = link "dotfiles/claude/skills/social-bookmarks";
    "claude/skills/tuicr".source = link "dotfiles/claude/skills/tuicr";
    "claude/skills/writing-agent-instructions".source =
      link "dotfiles/claude/skills/writing-agent-instructions";
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
    "claude-gpt56/skills/nix-environment-setup".source =
      link "dotfiles/claude/skills/nix-environment-setup";
    "claude-gpt56/skills/visual-verification".source =
      link "dotfiles/claude/skills/visual-verification";
    "claude-gpt56/skills/domain-context".source = link "dotfiles/claude/skills/domain-context";
    "claude-gpt56/skills/herdr".source = link "dotfiles/claude/skills/herdr";
    "claude-gpt56/skills/r-dev-shell".source = link "dotfiles/claude/skills/r-dev-shell";
    "claude-gpt56/skills/social-bookmarks".source = link "dotfiles/claude/skills/social-bookmarks";
    "claude-gpt56/skills/tuicr".source = link "dotfiles/claude/skills/tuicr";
    "claude-gpt56/skills/explain-session".source = link "dotfiles/claude/skills/explain-session";
    "claude-gpt56/skills/explain-session-sync".source =
      link "dotfiles/claude/skills/explain-session-sync";
    "claude-gpt56/explain-session".source = link "dotfiles/claude/explain-session";
    "claude-gpt56/hooks/explain-session-register.sh".source =
      link "dotfiles/claude/hooks/explain-session-register.sh";

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
    "claude-mattpocock/skills/visual-verification" = {
      source = link "dotfiles/claude/skills/visual-verification";
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
    "claude-mattpocock/skills/herdr" = {
      source = link "dotfiles/claude/skills/herdr";
      force = true;
    };
    "claude-mattpocock/skills/r-dev-shell" = {
      source = link "dotfiles/claude/skills/r-dev-shell";
      force = true;
    };
    "claude-mattpocock/skills/social-bookmarks" = {
      source = link "dotfiles/claude/skills/social-bookmarks";
      force = true;
    };
    "claude-mattpocock/skills/tuicr" = {
      source = link "dotfiles/claude/skills/tuicr";
      force = true;
    };
  };
}
