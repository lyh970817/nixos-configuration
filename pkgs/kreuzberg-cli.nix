{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gcc-unwrapped,
}:

stdenv.mkDerivation rec {
  pname = "kreuzberg-cli";
  version = "4.2.13";

  src = fetchurl {
    url = "https://github.com/kreuzberg-dev/kreuzberg/releases/download/v${version}/kreuzberg-cli-x86_64-unknown-linux-gnu.tar.gz";
    sha256 = "1vcbjvajlc05490v1drhhn3vlhsvdvj9xlcfn0zp9igd7sw60dnx";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ gcc-unwrapped.lib ];

  sourceRoot = "kreuzberg-cli-x86_64-unknown-linux-gnu";

  installPhase = ''
    runHook preInstall
    install -Dm755 kreuzberg $out/bin/kreuzberg
    runHook postInstall
  '';

  meta = with lib; {
    description = "Command-line interface for Kreuzberg document intelligence";
    homepage = "https://github.com/kreuzberg-dev/kreuzberg";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "kreuzberg";
  };
}
