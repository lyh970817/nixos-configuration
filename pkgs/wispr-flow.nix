{
  lib,
  appimageTools,
  fetchurl,
  runCommand,
}:

# Community repackage of the proprietary Wispr Flow Electron app
# (github.com/wispr-flow-linux/wispr-flow-linux): Wispr's Windows build with
# Linux patches and a native helper that reads the hotkey from evdev and pastes
# through /dev/uinput.
let
  pname = "wispr-flow";
  wrapperVersion = "1.0.4";
  wisprVersion = "1.6.957";
  version = "${wisprVersion}-${wrapperVersion}";

  src = fetchurl {
    url = "https://github.com/wispr-flow-linux/wispr-flow-linux/releases/download/v${wrapperVersion}%2Bwispr${wisprVersion}/wispr-flow-${version}-x86_64.AppImage";
    hash = "sha256-2jeeMDWVnkadE5lyjwb1ThKplYoxp5P/GgZ39OEtiMU=";
  };

  contents = appimageTools.extractType2 { inherit pname version src; };

  # AppRun passes --no-sandbox for AppImages, whose FUSE mount drops the
  # chrome-sandbox setuid bit. Unpacked here, Chromium can use its
  # user-namespace sandbox instead, so launch as the "nix" package type,
  # which keeps the sandbox on.
  sandboxed = runCommand "${pname}-${version}-sandboxed" { } ''
    cp -r ${contents} $out
    chmod -R u+w $out
    substituteInPlace $out/AppRun \
      --replace-fail "build_electron_args 'appimage'" "build_electron_args 'nix'"
  '';
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = sandboxed;

  extraPkgs = pkgs: [ pkgs.wl-clipboard ];

  extraInstallCommands = ''
    install -Dm644 ${contents}/ai.wisprflow.WisprFlow.desktop \
      $out/share/applications/ai.wisprflow.WisprFlow.desktop
    substituteInPlace $out/share/applications/ai.wisprflow.WisprFlow.desktop \
      --replace-fail 'Exec=AppRun %U' 'Exec=wispr-flow %U'
    install -Dm644 ${contents}/ai.wisprflow.WisprFlow.png \
      $out/share/icons/hicolor/256x256/apps/ai.wisprflow.WisprFlow.png
  '';

  meta = {
    description = "Wispr Flow voice dictation, repackaged for Linux";
    homepage = "https://github.com/wispr-flow-linux/wispr-flow-linux";
    license = lib.licenses.unfree;
    mainProgram = "wispr-flow";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
