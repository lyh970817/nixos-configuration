{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gcc-unwrapped,
}:

stdenv.mkDerivation rec {
  pname = "xberg-cli";
  version = "1.3.0";

  # Kreuzberg was renamed to Xberg (kreuzberg-dev/kreuzberg now redirects to
  # xberg-io/xberg) and versioning reset to 1.0.x, so the old kreuzberg-cli
  # 4.2.13 asset no longer exists and cannot be pinned.
  src = fetchurl {
    url = "https://github.com/xberg-io/xberg/releases/download/v${version}/xberg-cli-x86_64-unknown-linux-gnu.tar.gz";
    sha256 = "sha256-+aI5mpk8RqsRGy/YTQD318ZkCJspcw5YgS20VAfUYnc=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ gcc-unwrapped.lib ];

  sourceRoot = "xberg-cli-x86_64-unknown-linux-gnu";

  # Unlike the old archive, this one ships its own libheif, libaom, libx265,
  # libde265, libnuma and liblzma -- the LGPL codecs are dynamically linked and
  # redistributed beside the binary, which upstream resolves via $ORIGIN. They
  # must be installed and put back on the runpath that autoPatchelfHook rewrites.
  appendRunpaths = [ "${placeholder "out"}/lib" ];

  installPhase = ''
    runHook preInstall
    install -Dm755 xberg $out/bin/xberg
    install -Dm755 -t $out/lib *.so.*
    install -Dm644 -t $out/share/doc/${pname} LICENSE THIRD_PARTY_LICENSES.md
    runHook postInstall
  '';

  meta = with lib; {
    description = "Command-line interface for Xberg document intelligence (formerly Kreuzberg)";
    homepage = "https://github.com/xberg-io/xberg";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "xberg";
  };
}
