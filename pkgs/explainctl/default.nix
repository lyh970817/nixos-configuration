{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  coreutils,
  tylax,
}:

stdenvNoCC.mkDerivation {
  pname = "explainctl";
  version = "0.1.0";

  src = ./.;
  nativeBuildInputs = [ makeWrapper ];

  # tylax on the check PATH runs the real-t2l conversion tests in the
  # sandbox instead of skipping them.
  nativeCheckInputs = [ tylax ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${python3}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  # The wrapper only prefixes PATH: `claude`/`claude-gpt56`, `kitty`, and
  # `nvim` must come from the user environment, because the launchers are
  # Home Manager wrappers that own their gateway/proxy/theme setup. t2l is a
  # pure CLI, so it is baked in — submit arrives over SSH from the laptop,
  # where the non-interactive PATH is not guaranteed.
  installPhase = ''
    runHook preInstall
    install -Dm755 explainctl.py $out/libexec/explainctl/explainctl.py
    cp -r explainctl_lib $out/libexec/explainctl/explainctl_lib
    makeWrapper ${python3}/bin/python $out/bin/explainctl \
      --add-flags "$out/libexec/explainctl/explainctl.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          tylax
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Forked Claude explanation workspaces with a persistent Markdown tree";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "explainctl";
  };
}
