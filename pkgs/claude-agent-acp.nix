{
  lib,
  buildNpmPackage,
  fetchzip,
  jq,
  makeWrapper,
  nodejs,
  ripgrep,
}:

# ACP adapter for Claude Code, the default `acpx claude` agent. acpx would
# otherwise fetch it with `npx -y` at run time. It runs the Claude Agent SDK's
# own bundled Claude Code, not pkgs.claude-code, so it authenticates from
# CLAUDE_CONFIG_DIR like any other Claude Code build; the wrapper points it at
# the system ripgrep instead of the vendored binary, which expects a
# conventional loader path.
buildNpmPackage (finalAttrs: {
  pname = "claude-agent-acp";
  version = "0.79.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@agentclientprotocol/claude-agent-acp/-/claude-agent-acp-${finalAttrs.version}.tgz";
    hash = "sha256-WyVaA+Pp6BrPMevtu4nhMFz2xvP8OhkpsOkPig6uOEA=";
  };

  postPatch = ''
    cp ${./claude-agent-acp-package-lock.json} package-lock.json
    ${lib.getExe jq} --sort-keys 'del(.devDependencies, .scripts)' \
      package.json > package.json.patched
    mv package.json.patched package.json
  '';

  npmDepsHash = "sha256-gXNRr31ElsTO5ZnYO1TAXd5CpKXjjkP1wPvbjcmtFsI=";

  inherit nodejs;

  nativeBuildInputs = [ makeWrapper ];

  dontNpmBuild = true;

  postInstall = ''
    wrapProgram "$out/bin/claude-agent-acp" \
      --set DISABLE_AUTOUPDATER 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
  '';

  meta = {
    description = "Agent Client Protocol adapter for Claude Code";
    homepage = "https://github.com/agentclientprotocol/claude-agent-acp";
    downloadPage = "https://www.npmjs.com/package/@agentclientprotocol/claude-agent-acp";
    license = lib.licenses.asl20;
    mainProgram = "claude-agent-acp";
    platforms = [ "x86_64-linux" ];
  };
})
