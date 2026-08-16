{
  lib,
  buildPythonApplication,
  buildPythonPackage,
  fetchPypi,
  hatchling,
  browser-cookie3,
  click,
  httpx,
  pycryptodome,
  pyyaml,
  qrcode,
  rich,
}:

let
  # Xiaohongshu request-signature generator (x-s / x-s-common). Not in nixpkgs.
  # Taken as a wheel on purpose: the sdist's version comes from hatch-vcs, which
  # has no git metadata to read outside a checkout. Pure Python either way.
  xhshow = buildPythonPackage rec {
    pname = "xhshow";
    version = "0.2.0";
    format = "wheel";

    src = fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-Teb2Mv+RFiG1UzX3dyGH3NTu1BQUIFcSCje/1Gym1Ls=";
    };

    dependencies = [ pycryptodome ];

    doCheck = false;
    pythonImportsCheck = [ "xhshow" ];

    meta = {
      description = "Xiaohongshu web API signature generator";
      homepage = "https://github.com/cloxl/xhshow";
      license = lib.licenses.mit;
    };
  };
in
buildPythonApplication rec {
  pname = "xiaohongshu-cli";
  version = "0.6.4";
  pyproject = true;

  src = fetchPypi {
    pname = "xiaohongshu_cli";
    inherit version;
    hash = "sha256-kFiup9sTA09YTxWwRLNmudBASaRThiymBZjnjbnzzY4=";
  };

  build-system = [ hatchling ];

  # camoufox is dropped deliberately. Upstream declares it as a hard dependency
  # but imports it lazily, in exactly one place: `_ensure_camoufox_ready` in
  # xhs_cli/qr_login.py, which raises BrowserQrLoginUnavailable when it is
  # absent. It also downloads a patched Firefox at runtime, which does not run
  # on NixOS unaided. Nothing on the read path (`xhs favorites`, `search`,
  # `read`, ...) touches it, and the terminal QR login and the
  # `--cookie-source`/`~/.xiaohongshu-cli/cookies.json` auth paths do not
  # either -- only the browser-assisted QR variant does.
  pythonRemoveDeps = [ "camoufox" ];

  dependencies = [
    browser-cookie3
    click
    httpx
    pycryptodome
    pyyaml
    qrcode
    rich
    xhshow
  ];

  # The suite either calls the live Xiaohongshu API or needs a browser cookie
  # store; upstream itself gates the real ones behind a `smoke` marker.
  doCheck = false;
  pythonImportsCheck = [ "xhs_cli" ];

  meta = {
    description = "CLI for Xiaohongshu (RedNote): search, read, and list favorites";
    homepage = "https://github.com/jackwener/xiaohongshu-cli";
    license = lib.licenses.asl20;
    mainProgram = "xhs";
    platforms = lib.platforms.linux;
  };
}
