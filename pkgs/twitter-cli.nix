{
  lib,
  buildPythonApplication,
  buildPythonPackage,
  fetchPypi,
  hatchling,
  beautifulsoup4,
  browser-cookie3,
  click,
  curl-cffi,
  pyyaml,
  rich,
}:

let
  # X's per-request `x-client-transaction-id` header generator. Not in nixpkgs;
  # pure Python, beautifulsoup4 its only runtime dependency. Taken as a wheel:
  # upstream's sdist ships a setup.py that reads a requirements.txt it does not
  # include, so the sdist cannot be built at all.
  xclienttransaction = buildPythonPackage rec {
    pname = "xclienttransaction";
    version = "1.0.3";
    format = "wheel";

    src = fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-9z3SpLaFb5j6RfDNJsmg/cCyzroOebVSPN+KrH78Wf4=";
    };

    dependencies = [ beautifulsoup4 ];

    # No test suite ships in the sdist; the import is offline and cheap.
    doCheck = false;
    pythonImportsCheck = [ "x_client_transaction" ];

    meta = {
      description = "Generator for X's x-client-transaction-id request header";
      homepage = "https://github.com/iSarabjitDhiman/XClientTransaction";
      license = lib.licenses.mit;
    };
  };
in
buildPythonApplication rec {
  pname = "twitter-cli";
  version = "0.8.5";
  pyproject = true;

  src = fetchPypi {
    pname = "twitter_cli";
    inherit version;
    hash = "sha256-gKHwND+bYybYa4wUeo7asQa8R2Zh6d7YBzaObEzV2Wg=";
  };

  build-system = [ hatchling ];

  dependencies = [
    beautifulsoup4
    browser-cookie3
    click
    curl-cffi
    pyyaml
    rich
    xclienttransaction
  ];

  # Every test path either talks to x.com or needs a browser cookie store.
  doCheck = false;
  pythonImportsCheck = [ "twitter_cli" ];

  meta = {
    description = "Read-only CLI for Twitter/X feed, bookmarks, and user timelines";
    homepage = "https://github.com/jackwener/twitter-cli";
    license = lib.licenses.asl20;
    mainProgram = "twitter";
    platforms = lib.platforms.linux;
  };
}
