{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  nodejs_22,
  pnpmConfigHook,
  pnpm_10,
}:
let
  pnpm = pnpm_10.override { nodejs = nodejs_22; };

  mkReleaseBinary =
    {
      pname,
      version,
      url,
      hash,
      description,
    }:
    stdenvNoCC.mkDerivation {
      inherit pname version;
      src = fetchurl { inherit url hash; };
      sourceRoot = ".";
      dontBuild = true;
      installPhase = ''
        runHook preInstall
        install -Dm755 ${pname} "$out/bin/${pname}"
        runHook postInstall
      '';
      meta = {
        inherit description;
        homepage = "https://github.com/kunchenguid/${pname}";
        license = lib.licenses.mit;
        mainProgram = pname;
        sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
        platforms = [ "x86_64-linux" ];
      };
    };

  mkAxiCli =
    {
      pname,
      version,
      repo,
      rev,
      hash,
      pnpmDepsHash,
      bin,
      description,
    }:
    stdenvNoCC.mkDerivation (finalAttrs: {
      inherit pname version;
      src = fetchFromGitHub {
        owner = "kunchenguid";
        inherit repo rev hash;
      };
      pnpmDeps = fetchPnpmDeps {
        inherit (finalAttrs) pname version src;
        inherit pnpm;
        fetcherVersion = 3;
        hash = pnpmDepsHash;
      };
      nativeBuildInputs = [
        makeWrapper
        nodejs_22
        pnpm
        pnpmConfigHook
      ];
      buildPhase = "pnpm run build";
      installPhase = ''
        runHook preInstall
        package="$out/lib/node_modules/${pname}"
        mkdir -p "$package"
        cp -r dist node_modules package.json "$package"
        makeWrapper ${nodejs_22}/bin/node "$out/bin/${pname}" \
          --add-flags "$package/${bin}"
        runHook postInstall
      '';
      meta = {
        inherit description;
        homepage = "https://github.com/kunchenguid/${repo}";
        license = lib.licenses.mit;
        mainProgram = pname;
        platforms = lib.platforms.linux;
      };
    });
in
{
  treehouse = mkReleaseBinary {
    pname = "treehouse";
    version = "2.1.1";
    url = "https://github.com/kunchenguid/treehouse/releases/download/v2.1.1/treehouse-v2.1.1-linux-amd64.tar.gz";
    hash = "sha256-L+PgEiCuUalnw+W6bM8Q7IO9uujkIDaNGUKFqNBMnvg=";
    description = "Disposable Git worktree manager";
  };

  no-mistakes = mkReleaseBinary {
    pname = "no-mistakes";
    version = "1.41.2";
    url = "https://github.com/kunchenguid/no-mistakes/releases/download/v1.41.2/no-mistakes-v1.41.2-linux-amd64.tar.gz";
    hash = "sha256-oQDFi9/n359Zjs7DJVPV+9jrAHmRL8gw82IBH9nciCU=";
    description = "Evidence-driven coding-agent validation gates";
  };

  gh-axi = mkAxiCli {
    pname = "gh-axi";
    version = "0.1.29";
    repo = "gh-axi";
    rev = "09c488ec5bb22d068fbca1ab58212e9f63fd490c";
    hash = "sha256-xGabDo12fh+YO1ihSo6fyh8bYiELH+iWRDPZ37dMzNI=";
    pnpmDepsHash = "sha256-gLCR/5bGVOyacNU/QjDG8xvf7eg5bMNZ/UBALnTNssg=";
    bin = "dist/bin/gh-axi.js";
    description = "AXI-compliant GitHub CLI wrapper";
  };

  chrome-devtools-axi = mkAxiCli {
    pname = "chrome-devtools-axi";
    version = "0.1.28";
    repo = "chrome-devtools-axi";
    rev = "f6a9cb1b6228efcb2f541c2d08b67a026078c5a5";
    hash = "sha256-ST2x1+KQM4X/3KtbHUr+O5o6m8CLB50SzDVzMLbspno=";
    pnpmDepsHash = "sha256-eyOhZEsGecgLBvxIBPPvjw9MSJZ4rXIFyktz+Ax9qkE=";
    bin = "dist/bin/chrome-devtools-axi.js";
    description = "AXI-compliant Chrome DevTools CLI wrapper";
  };

  lavish-axi = mkAxiCli {
    pname = "lavish-axi";
    version = "0.1.44";
    repo = "lavish-axi";
    rev = "995707ecc22e1a4dac28a550fd7c00d8ad913d11";
    hash = "sha256-UquvoMBaaqlXt0i/XIcSIjGa/U/+/mm0I5EeBrV6q5s=";
    pnpmDepsHash = "sha256-ssuzj9LP5gvFJqtcbATRikCdefLKWPNzaa+5n26ggiI=";
    bin = "dist/cli.mjs";
    description = "AXI-rich HTML review workspace";
  };

  tasks-axi = mkAxiCli {
    pname = "tasks-axi";
    version = "0.2.4";
    repo = "tasks-axi";
    rev = "f1ba21a69137bb771ee1051c2b6179c3f4c8c4f4";
    hash = "sha256-GuD6gjE09IObnZr6kKWvbx56WOBRvbtuXOXRrKb2BUo=";
    pnpmDepsHash = "sha256-3KdnJSGunTKVjvB63hb49ODw8ujkTdBNC0f1jHBX0zY=";
    bin = "dist/bin/tasks-axi.js";
    description = "AXI task and backlog CLI";
  };

  quota-axi = mkAxiCli {
    pname = "quota-axi";
    version = "0.1.16";
    repo = "quota-axi";
    rev = "335be6f7ccbb637feb1e0c2b4d30268af41f9f4f";
    hash = "sha256-YiYPGwEnG4Tjh0LBDeB+NxWaFgmTVnM9tdKxOrMsHb4=";
    pnpmDepsHash = "sha256-L1rfVYyXTXR1uJl2HWzGgI0djEh/qlPXZQ+n3E4EyGU=";
    bin = "dist/bin/quota-axi.js";
    description = "AXI local coding-agent quota reporter";
  };
}
