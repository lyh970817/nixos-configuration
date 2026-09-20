{
  lib,
  buildNpmPackage,
  fetchzip,
  jq,
  nodejs,
}:

# ACP client CLI that backpass drives every model call through. The npm
# release ships the built dist/ but no lockfile, so a production-only lock is
# kept beside this expression; devDependencies and lifecycle scripts (husky)
# are dropped from package.json to match it.
buildNpmPackage (finalAttrs: {
  pname = "acpx";
  version = "0.17.1";

  src = fetchzip {
    url = "https://registry.npmjs.org/acpx/-/acpx-${finalAttrs.version}.tgz";
    hash = "sha256-/+JZzKq/bDMq5Mdz75NR3kUzSQn/HRJG1FL6bvKKuK4=";
  };

  postPatch = ''
    cp ${./acpx-package-lock.json} package-lock.json
    ${lib.getExe jq} --sort-keys 'del(.devDependencies, .scripts)' \
      package.json > package.json.patched
    mv package.json.patched package.json
  '';

  npmDepsHash = "sha256-PUTRvBb6Qe3pGoZtZ1aKmdn2DVRFpZWnwbPtq5QsKPk=";

  inherit nodejs;

  dontNpmBuild = true;

  meta = {
    description = "Headless CLI for driving coding agents over the Agent Client Protocol";
    homepage = "https://github.com/openclaw/acpx";
    downloadPage = "https://www.npmjs.com/package/acpx";
    license = lib.licenses.mit;
    mainProgram = "acpx";
    platforms = [ "x86_64-linux" ];
  };
})
