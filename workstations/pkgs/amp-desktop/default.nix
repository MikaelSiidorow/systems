# Amp's Linux desktop app, published as a .deb but not listed on
# ampcode.com/download; the AUR package amp-desktop-bin tracks the current
# version. The app is a JavaScript bundle, so it runs on nixpkgs' Electron of
# the major version the .deb ships with. Adapted from kahlstrm/config.
{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  asar,
  makeWrapper,
  electron_44,
  xdg-utils,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "amp-desktop";
  version = "0.1.29908343";

  src = fetchurl {
    url = "https://static.ampcode.com/linux/${finalAttrs.version}/amp-desktop-${finalAttrs.version}-amd64.deb";
    hash = "sha256-Z3EOt6cupJA/dzqKxJEg9KGRBoknmJlALjNVFzoHwYY=";
  };

  nativeBuildInputs = [
    dpkg
    asar
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall

    asar extract opt/amp/resources/app.asar $out/share/amp-desktop
    # Open at Login saves Electron's and the bundle's store paths, which an
    # update and a GC remove. Save the wrapper's name, as the .desktop does.
    substituteInPlace $out/share/amp-desktop/dist/main.js \
      --replace-fail 'process.execPath,
      ...app.isPackaged ? [] : [app.getAppPath()],' '"amp-desktop",'
    cp -r usr/share/icons $out/share/icons
    install -Dm644 usr/share/applications/amp-desktop.desktop -t $out/share/applications
    substituteInPlace $out/share/applications/amp-desktop.desktop \
      --replace-fail /opt/amp/amp-desktop amp-desktop

    # xdg-open opens the browser for sign-in and links.
    makeWrapper ${lib.getExe electron_44} $out/bin/amp-desktop \
      --add-flags $out/share/amp-desktop \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --inherit-argv0

    runHook postInstall
  '';

  meta = {
    description = "Amp, the coding agent, as a desktop app";
    homepage = "https://ampcode.com";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "amp-desktop";
  };
})
