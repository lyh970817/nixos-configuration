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
  version = "0.19.4";

  src = fetchzip {
    url = "https://registry.npmjs.org/acpx/-/acpx-${finalAttrs.version}.tgz";
    hash = "sha256-RTDnP4/XIr8lV6FCM2TmPmckTw3mdL1mg/S8K5vrJ3Y=";
  };

  postPatch = ''
    cp ${./acpx-package-lock.json} package-lock.json
    ${lib.getExe jq} --sort-keys 'del(.devDependencies, .scripts)' \
      package.json > package.json.patched
    mv package.json.patched package.json
  '';

  npmDepsHash = "sha256-q9RAARKOgk6EhISyf6dFUCLDvh0CPSCQypSbzsZ6WMw=";

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
