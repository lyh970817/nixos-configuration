{
  lib,
  fetchFromGitHub,
  buildGoModule,
  go_1_26,
}:

let
  buildGo126Module = buildGoModule.override { go = go_1_26; };
in
buildGo126Module rec {
  pname = "digg-pp-cli";
  version = "2026.9.1";

  src = fetchFromGitHub {
    owner = "mvanhorn";
    repo = "printing-press-library";
    rev = "81f5764eda401077520268afe74913c0f21f5b7e";
    hash = "sha256-yarE54JcWjvSnUXVTxI3XA7imvKR8ytY6X6tOO+ZdK8=";
  };

  modRoot = "library/media-and-entertainment/digg";
  subPackages = [ "cmd/digg-pp-cli" ];

  postPatch = ''
    substituteInPlace library/media-and-entertainment/digg/go.mod \
      --replace-fail "go 1.26.6" "go 1.26"
  '';

  vendorHash = "sha256-W8I7Xzu6wLlfaRMXzTTtcgzTDRcg64f+kgSxw/av1k8=";

  meta = with lib; {
    description = "Read-only CLI for Digg AI story leaderboards, GitHub feeds, and pipeline events";
    homepage = "https://printingpress.dev";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "digg-pp-cli";
  };
}
