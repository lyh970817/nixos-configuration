{
  lib,
  buildNpmPackage,
  fetchzip,
  jq,
  nodejs_22,
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-coding-agent";
  # Pinned deliberately: the openai-server-compaction extension declares a
  # peer range of >=0.80.9 <0.81.0. Bump both together — see
  # docs/pi-coding-agent.md.
  version = "0.80.9";

  src = fetchzip {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${finalAttrs.version}.tgz";
    hash = "sha256-xG2+APfl3zmzoNLbcoOjnGpY+LHfHe9P4rCAAmZ0hiA=";
  };

  # Upstream's npm-shrinkwrap.json omits `integrity` for the three first-party
  # @earendil-works entries, which makes prefetch-npm-deps abort. Patch the
  # published sha512 digests back in; this runs for both the dependency
  # fetch and the build, so npmDepsHash stays stable. jq is referenced by
  # store path because buildNpmPackage forwards postPatch to fetchNpmDeps but
  # not nativeBuildInputs.
  postPatch = ''
    ${lib.getExe jq} --sort-keys \
      '.packages["node_modules/@earendil-works/pi-agent-core"].integrity = "sha512-tObjeOLiw1kYUciBi9R+rRyc4QGK+1akbLLQHvzsn2JrrV2btUdDncJ7jMIR5TKvOYKzKxAwQSl/5k7h3Tjrrg=="
       | .packages["node_modules/@earendil-works/pi-ai"].integrity = "sha512-kHsH5nO4FU7mbKnskK0BVPVuWzNb2DrZtiN1fb6LamP+6BMI8xEZiAOw2fqs4VudvlMQgOLjtbgErv+kNJRPIg=="
       | .packages["node_modules/@earendil-works/pi-tui"].integrity = "sha512-unPTW8hRgIHEGjV8mJJ2jqm+fzgnRubes6V2FPk9ay1W9ZLofcpYQ3NDfrODXSci+oKbBpX9JyYUMfQV6jCA/A=="' \
      npm-shrinkwrap.json > npm-shrinkwrap.json.patched
    mv npm-shrinkwrap.json.patched npm-shrinkwrap.json

    # That shrinkwrap was generated with --omit=dev, so it has no entries for
    # the devDependencies package.json still declares. `npm ci` resolves the
    # full tree before pruning, so it would reach for @types/* over the network
    # and die with ENOTCACHED. Drop the dev block to match the lockfile.
    ${lib.getExe jq} --sort-keys 'del(.devDependencies)' \
      package.json > package.json.patched
    mv package.json.patched package.json
  '';

  npmDepsHash = "sha256-YrRVm5a9wxYwc/4vs4r6xJwkAzSSlYggv1CPMvuoUVw=";

  nodejs = nodejs_22;

  # The tarball ships a prebuilt dist/, so there is no compile step.
  dontNpmBuild = true;

  meta = {
    description = "pi coding agent CLI";
    homepage = "https://github.com/earendil-works/pi";
    downloadPage = "https://www.npmjs.com/package/@earendil-works/pi-coding-agent";
    license = lib.licenses.mit;
    mainProgram = "pi";
    # The tarball ships a prebuilt dist/ rather than the TypeScript sources.
    sourceProvenance = with lib.sourceTypes; [ binaryBytecode ];
    platforms = [ "x86_64-linux" ];
  };
})
