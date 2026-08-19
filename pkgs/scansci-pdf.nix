{
  lib,
  buildPythonApplication,
  fetchPypi,
  setuptools,
  pycryptodome,
  beautifulsoup4,
  fastapi,
  jinja2,
  lxml,
  mcp,
  pysocks,
  requests,
  typer,
  uvicorn,
}:

# Academic paper fetcher, packaged deliberately *without* its browser extras.
# Every browser code path in upstream funnels through a bare
# `from cloakbrowser import launch` inside a try/except ImportError, so leaving
# the `cloakbrowser` extra out is the kill switch that guarantees no browser is
# ever launched. Do not add it. The wheel is pure Python (Root-Is-Purelib, no
# compiled modules -- `_core/` ships only pure-Python fallbacks), so no
# autoPatchelfHook or FHS wrapper is involved.
#
# Reach it through the `scansci-oa` wrapper (home/programs/scansci-oa.nix), not
# directly: importing `scansci_pdf` sets NO_PROXY=* process-wide and
# monkey-patches ssl.SSLContext.load_default_certs, so it must stay in its own
# process and never be imported into another tool.
buildPythonApplication rec {
  pname = "scansci-pdf";
  version = "1.9.0";
  pyproject = true;

  src = fetchPypi {
    pname = "scansci_pdf";
    inherit version;
    hash = "sha256-FYkvD2WQZhMtadWg9gYsp+O3ljHPWLT7KP3dH4H9rHU=";
  };

  # setup.py encrypts data/webvpn.json -> webvpn.dat with pycryptodome at build
  # time; without it the build backend fails before compiling anything.
  build-system = [
    setuptools
    pycryptodome
  ];

  dependencies = [
    beautifulsoup4
    fastapi
    jinja2
    lxml # fetcher.py hardcodes BeautifulSoup(html, "lxml")
    mcp
    pysocks # the requests[socks] extra
    requests
    typer
    uvicorn
  ];

  postPatch = ''
    # `get` hardcodes use_tor=True/use_vpnsci=True, overriding the config file.
    # Both belong to the institutional/anonymising ladder we deliberately leave
    # switched off.
    substituteInPlace src/scansci_pdf/main.py \
      --replace-fail \
        'scihub_enabled=True, use_tor=True, use_vpnsci=True,' \
        'scihub_enabled=True, use_tor=False, use_vpnsci=False,'

    # Belt and braces: ensure_tor() otherwise downloads a Tor Expert Bundle
    # tarball at runtime -- a prebuilt glibc binary that cannot run on NixOS.
    substituteInPlace src/scansci_pdf/tor.py \
      --replace-fail \
        'from .embedded_tor import get_embedded_tor' \
        'raise RuntimeError("embedded Tor is disabled by packaging")'
  '';

  # Upstream's tests hit publisher endpoints and probe for a browser runtime.
  doCheck = false;
  pythonImportsCheck = [ "scansci_pdf" ];

  meta = {
    description = "Academic paper downloader, packaged without browser automation";
    homepage = "https://github.com/Rimagination/scansci-pdf";
    license = lib.licenses.asl20;
    mainProgram = "scansci-pdf";
    platforms = lib.platforms.linux;
  };
}
