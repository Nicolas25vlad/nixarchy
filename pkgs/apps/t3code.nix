{
  lib,
  appimageTools,
  fetchurl,
}:
let
  pname = "t3code";
  version = "0.0.33";
  # Named so the updater can rewrite it by key.
  hashes.appimage = "415c8648f43c3d22d572f27f2c50fdc8c310ea7fcde9537b903e1e2f1c8775a1";
  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    sha256 = hashes.appimage;
  };
  # Pulls the .desktop entry and icons out of the image so the app appears in
  # the launcher rather than only on the command line.
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${contents}/t3code.desktop \
      $out/share/applications/t3code.desktop 2>/dev/null || true
    cp -r ${contents}/usr/share/icons $out/share/ 2>/dev/null || true
    substituteInPlace $out/share/applications/t3code.desktop \
      --replace-quiet 'Exec=AppRun' 'Exec=${pname}' || true
  '';

  meta = {
    description = "Open-source control plane for coding agents";
    homepage = "https://t3.codes";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = pname;
  };
}
