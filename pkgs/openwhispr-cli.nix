{
  lib,
  fetchurl,
  stdenvNoCC,
  makeWrapper,
  nodejs_22,
}:

let
  pname = "openwhispr-cli";
  version = "0.1.0";

  commander = fetchurl {
    url = "https://registry.npmjs.org/commander/-/commander-12.1.0.tgz";
    hash = "sha256-Vq/8bdr+SG+UtCiuKCPQWc9g1Nri8z6q8bHsQwb3MXM=";
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@openwhispr/cli/-/cli-${version}.tgz";
    hash = "sha256-6EwuRggqJpo2THA0O8vm1waotOFElDVfBMAOjO+xwfU=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    package_dir="$out/lib/node_modules/@openwhispr/cli"
    mkdir -p "$package_dir"
    cp -R . "$package_dir"

    mkdir -p "$package_dir/node_modules/commander"
    tar -xzf ${commander} -C "$package_dir/node_modules/commander" --strip-components=1

    makeWrapper ${nodejs_22}/bin/node "$out/bin/openwhispr" \
      --add-flags "$package_dir/dist/index.js"

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenWhispr CLI for local desktop bridge or cloud API access";
    homepage = "https://openwhispr.com/cli/install";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "openwhispr";
  };
}
