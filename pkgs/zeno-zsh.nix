{
  lib,
  fetchFromGitHub,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "zeno-zsh";
  version = "unstable-2026-04-05";

  src = fetchFromGitHub {
    owner = "yuki-yano";
    repo = "zeno.zsh";
    rev = "2e8fbecce0fc3692a5fcc9033ecca7ab35263e56";
    hash = "sha256-05+w1WP/SHKp97JTGsvO3csI123U7py+fVSKnAWiUNY=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/zeno.zsh"
    cp -R . "$out/share/zeno.zsh"
    runHook postInstall
  '';

  meta = {
    description = "Zsh fuzzy completion and utility plugin with Deno";
    homepage = "https://github.com/yuki-yano/zeno.zsh";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
