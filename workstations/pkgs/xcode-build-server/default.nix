{
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  lib,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "xcode-build-server";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "SolaWing";
    repo = "xcode-build-server";
    tag = "v${finalAttrs.version}";
    hash = "sha256-AUGDoMeW/FSMJLG7uR580cMpytYQBFV2PXE3LBNaiFQ=";
  };

  nativeBuildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec
    cp -R . $out/libexec/xcode-build-server
    patchShebangs $out/libexec/xcode-build-server/xcode-build-server
    ln -s $out/libexec/xcode-build-server/xcode-build-server $out/bin/xcode-build-server
    runHook postInstall
  '';

  meta = {
    description = "Build server protocol implementation for Xcode projects";
    homepage = "https://github.com/SolaWing/xcode-build-server";
    license = lib.licenses.mit;
    mainProgram = "xcode-build-server";
    platforms = lib.platforms.darwin;
  };
})
