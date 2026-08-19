{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
}:

let
  pythonEnv = python3.withPackages (
    ps: with ps; [
      beautifulsoup4
      lxml
      requests
    ]
  );
in
stdenvNoCC.mkDerivation {
  pname = "annas-books";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  # Offline: fixtures for the parsers, a fake session for the client, a fake
  # probe for mirror failover. Nothing here touches the network or the quota.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ${pythonEnv}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 annas_books.py $out/libexec/annas-books/annas_books.py
    cp -r annas_books_lib $out/libexec/annas-books/annas_books_lib
    makeWrapper ${pythonEnv}/bin/python $out/bin/annas-books \
      --add-flags "$out/libexec/annas-books/annas_books.py"
    runHook postInstall
  '';

  meta = {
    description = "Anna's Archive membership client for books";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "annas-books";
  };
}
