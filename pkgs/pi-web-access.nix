{
  lib,
  buildNpmPackage,
  fetchzip,
  jq,
  nodejs_22,
}:

buildNpmPackage (finalAttrs: {
  pname = "pi-web-access";
  version = "0.14.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/pi-web-access/-/pi-web-access-${finalAttrs.version}.tgz";
    hash = "sha256-fLoO5JATPpnfVeeE5LZsp2is1um3FC58VsEpGcDK9qw=";
  };

  # The npm release ships raw TypeScript but no lockfile. Keep a production-only
  # lock alongside this expression so Nix fetches exactly the runtime closure;
  # Pi supplies the package's @earendil-works peer dependencies itself.
  postPatch = ''
    cp package.json package.json.original
    cp ${./pi-web-access-package-lock.json} package-lock.json
    ${lib.getExe jq} --sort-keys 'del(.devDependencies, .peerDependencies)' \
      package.json > package.json.patched
    mv package.json.patched package.json
  '';

  npmDepsHash = "sha256-HK6fRqWa872J/1kBMovjprpCKs4aHU4XVkrAv4j6rJc=";

  nodejs = nodejs_22;

  # Pi's jiti loader runs the extension's TypeScript directly.
  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    for source in *; do
      case "$source" in
        node_modules | package-lock.json | package.json | package.json.original) ;;
        *) cp -r "$source" "$out/" ;;
      esac
    done
    install -Dm644 package.json.original "$out/package.json"
    cp -r node_modules "$out/node_modules"
    chmod -R u+w "$out/node_modules"

    runHook postInstall
  '';

  meta = {
    description = "Web search and URL fetching extension for the pi coding agent";
    homepage = "https://github.com/nicobailon/pi-web-access";
    downloadPage = "https://www.npmjs.com/package/pi-web-access";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
})
