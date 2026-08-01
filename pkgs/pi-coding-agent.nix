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
  version = "0.83.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-${finalAttrs.version}.tgz";
    hash = "sha256-cJf+Szh2Ldp+x4AB57kEMMhJ+69xcyW/6BCXROMiVeY=";
  };

  # Upstream's npm-shrinkwrap.json omits `integrity` for the three first-party
  # @earendil-works entries, which makes prefetch-npm-deps abort. Patch the
  # published sha512 digests back in; this runs for both the dependency
  # fetch and the build, so npmDepsHash stays stable. jq is referenced by
  # store path because buildNpmPackage forwards postPatch to fetchNpmDeps but
  # not nativeBuildInputs.
  postPatch = ''
    ${lib.getExe jq} --sort-keys \
      '.packages["node_modules/@earendil-works/pi-agent-core"].integrity = "sha512-RorGp9OH5l3ElpuC5a5ZQ2eWcchZGXflXRzVGkV99y3y6tT+LLNyxoYIdVKvTKWEObwhExeQbTH0fI2tE4iX4g=="
       | .packages["node_modules/@earendil-works/pi-ai"].integrity = "sha512-m3IZD4g3er0V8TC9+Vpgw/sjTKqcJlkcIBy/JvsgRubuuik3tAVzyugUg4rVrShIkkOT69mEd34NEqKUIsl6JQ=="
       | .packages["node_modules/@earendil-works/pi-tui"].integrity = "sha512-IoYrb0rORjELmEpNtoCA/U8je3KopMkRAVJRdSzvXRvgb+Huo1gNh8Q5CSZvNOiYtDxJdj2tYZZHZ4B3+IN3hA=="' \
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

  npmDepsHash = "sha256-fQ/phHywWTJM3dtHAhT2IcKiL+5I2eC4Gult++QuGOU=";

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
