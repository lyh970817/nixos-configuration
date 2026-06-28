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
  version = "2026.6.2";

  src = fetchFromGitHub {
    owner = "mvanhorn";
    repo = "printing-press-library";
    rev = "c58c42effc763f09d782982c1e0e759ac66f6545";
    hash = "sha256-qfvIN7hSz4wOBxQ1F+8mEVyngEZvB4b/aGi8QezxW84=";
  };

  modRoot = "library/media-and-entertainment/digg";
  subPackages = [ "cmd/digg-pp-cli" ];

  postPatch = ''
    substituteInPlace library/media-and-entertainment/digg/go.mod \
      --replace-fail "go 1.26.4" "go 1.26"
  '';

  vendorHash = "sha256-HKZfb0yW8E6SKKN56E3XYVqA6S3M7niJYIHO180mPUw=";

  meta = with lib; {
    description = "Read-only CLI for Digg AI story leaderboards, GitHub feeds, and pipeline events";
    homepage = "https://printingpress.dev";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "digg-pp-cli";
  };
}
