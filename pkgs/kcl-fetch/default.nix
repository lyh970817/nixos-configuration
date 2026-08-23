{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  chromium,
  # Tailscale/MagicDNS name of the other machine in the pair, from
  # `portable.peerHost`. Baked in so `kcl-fetch login --on` (no value) knows
  # which host to hop to; empty means `--on` needs an explicit host.
  peerHost ? "",
}:

let
  # `playwright` here is nixpkgs' patched build: `compute_driver_executable` is
  # rewritten to point at the store's nodejs and playwright-core `cli.js`, so
  # the driver never tries to fetch itself. The *browser* is still ours to
  # supply -- upstream's browser downloads are prebuilt glibc binaries that do
  # not run on NixOS -- hence the pinned `chromium` below.
  pythonEnv = python3.withPackages (ps: with ps; [ playwright ]);
in
stdenvNoCC.mkDerivation {
  pname = "kcl-fetch";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  # Offline. The gate is exercised against an injected clock, so the rolling
  # 3-hour and 24-hour windows are tested in milliseconds; the browser, LibKey
  # and Crossref are all behind injected openers. Nothing here reaches a
  # publisher, an institution, or the network.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONPATH=$PWD:$PWD/tests ${pythonEnv}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 kcl_fetch.py $out/libexec/kcl-fetch/kcl_fetch.py
    cp -r kcl_fetch_lib $out/libexec/kcl-fetch/kcl_fetch_lib
    makeWrapper ${pythonEnv}/bin/python $out/bin/kcl-fetch \
      --add-flags "$out/libexec/kcl-fetch/kcl_fetch.py" \
      --set PYTHONPATH "$out/libexec/kcl-fetch" \
      --set KCL_FETCH_CHROMIUM "${lib.getBin chromium}/bin/chromium" \
      ${lib.optionalString (peerHost != "") ''--set-default KCL_FETCH_PEER_HOST "${peerHost}"''}
    runHook postInstall
  '';

  meta = {
    description = "Single-article institutional retrieval through King's College London";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "kcl-fetch";
  };
}
