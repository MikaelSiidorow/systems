# Meetily, a local meeting recorder and transcriber (Whisper or Parakeet),
# from the upstream .deb. It is a Tauri app with onnxruntime and ffmpeg linked
# in statically, so it only needs the WebKitGTK stack, audio and Vulkan.
# Models download at runtime into ~/.local/share/com.meetily.ai.
{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  alsa-lib,
  libpulseaudio,
  vulkan-loader,
  webkitgtk_4_1,
  gtk3,
  libsoup_3,
  openssl,
  xz,
  dbus,
  libayatana-appindicator,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "meetily";
  version = "0.5.0";

  src = fetchurl {
    url = "https://github.com/Zackriya-Solutions/meetily/releases/download/v${finalAttrs.version}/meetily_${finalAttrs.version}_amd64.deb";
    hash = "sha256-x8nVapv4tPe0G2TY0cBNgXTvFQ9FAEOSPigo6qiV1AQ=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    libpulseaudio
    vulkan-loader
    webkitgtk_4_1
    gtk3
    libsoup_3
    openssl
    xz
    dbus
  ];

  # Tauri loads the tray library with dlopen.
  runtimeDependencies = [ libayatana-appindicator ];

  # Only the app needs the GTK environment, not its ffmpeg or llama sidecars.
  dontWrapGApps = true;
  postFixup = ''
    wrapGApp $out/opt/meetily/usr/bin/meetily
  '';

  installPhase = ''
    runHook preInstall
    # Tauri finds its sidecars next to the binary and its templates in
    # ../lib/meetily when the binary sits in a usr/bin directory. A private
    # prefix keeps the bundled ffmpeg off PATH.
    mkdir -p $out/opt/meetily $out/bin
    cp -r usr $out/opt/meetily/
    ln -s $out/opt/meetily/usr/bin/meetily $out/bin/meetily
    mv $out/opt/meetily/usr/share $out/share
    runHook postInstall
  '';

  meta = {
    description = "Privacy-first AI meeting assistant with local transcription";
    homepage = "https://github.com/Zackriya-Solutions/meetily";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "meetily";
  };
})
