{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  coreutils,
}:

stdenvNoCC.mkDerivation {
  pname = "explainctl";
  version = "0.1.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  # The wrapper only prefixes PATH: `claude`/`claude-gpt56`, `kitty`, and
  # `nvim` must come from the user environment, because the launchers are
  # Home Manager wrappers that own their gateway/proxy/theme setup.
  installPhase = ''
    runHook preInstall
    install -Dm755 explainctl.py $out/libexec/explainctl/explainctl.py
    cp -r explainctl_lib $out/libexec/explainctl/explainctl_lib
    makeWrapper ${python3}/bin/python $out/bin/explainctl \
      --add-flags "$out/libexec/explainctl/explainctl.py" \
      --prefix PATH : ${lib.makeBinPath [ coreutils ]}
    runHook postInstall
  '';

  meta = {
    description = "Forked Claude explanation workspaces with a persistent Markdown tree";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "explainctl";
  };
}
