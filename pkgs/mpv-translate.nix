{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "mpv-translate";
  version = "0.1.0-unstable-2026-03-29";
  pyproject = true;

  # dayo6/mpv-translate is no longer public. Its exact commit remains available
  # in the original fork network; this is not alexkoay's mpv-whisper HEAD.
  src = fetchFromGitHub {
    owner = "alexkoay";
    repo = "mpv-whisper";
    rev = "31dbbf60acd23f182fbc87c56b84f401de14418a";
    hash = "08xfvympkbxna7pdzw3ylxsca78fsbkc32i6qxxcc09azs5sq6sf";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    attrs
    av
    cattrs
    click
    faster-whisper
    more-itertools
    numpy
    python-mpv-jsonipc
    toml
    transformers
    sentencepiece
    sacremoses
    (torch.override {
      cudaSupport = false;
      rocmSupport = false;
    })
  ];

  # Upstream's wheel excludes config.toml. Keep that layout: its loader picks
  # the FIRST existing config, so bundling the CUDA/Japanese defaults would
  # hide the managed user config rather than let it override those defaults.
  pythonImportsCheck = [ "mpv_translate.cli" ];
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test ! -e "$out/${python3Packages.python.sitePackages}/mpv_translate/config.toml"
    "$out/bin/mpv-translate" --help > /dev/null
    "$out/bin/mpv-translate-direct" --help > /dev/null
    runHook postInstallCheck
  '';

  postInstall = ''
    install -Dm644 README.md "$out/share/doc/mpv-translate/README-upstream.md"
    install -Dm644 ${./mpv-translate.md} "$out/share/doc/mpv-translate/README.md"
  '';

  meta = {
    description = "Opt-in audio read-ahead and bilingual subtitles for mpv";
    homepage = "https://github.com/dayo6/mpv-translate";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "mpv-translate";
  };
}
