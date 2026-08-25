# Shared builder for the Electron apps Omarchy installs from .deb files.
#
# Both are the same shape: an unpacked Electron tree under /opt, a .desktop
# entry pointing at an absolute /opt path, and icons under /usr/share. The
# only per-app parts are the URL, the directory name and the executable name.
{
  lib,
  stdenv,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libnotify,
  libsecret,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  udev,
  libGL,
  vulkan-loader,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libXScrnSaver,
  libxtst,
  libxcb,
  xdg-utils,
  libusb1,
}:
{
  pname,
  version,
  src,
  # Path to the app tree INSIDE the .deb. Not always /opt: Grok Bot ships
  # under "opt/Grok Bot" (space and all) while ChatGPT uses usr/lib/chatgpt.
  srcDir,
  exeName, # executable inside that directory, e.g. "ChatGPT"
  # Command name to expose in bin/. Not always the same as the executable:
  # ChatGPT ships its binary capitalised but its .desktop calls `chatgpt`.
  binName ? exeName,
  desktopName ? pname,
  meta ? { },
}:
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libnotify
    libsecret
    libxkbcommon
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libXScrnSaver
    libxtst
    libxcb
    libusb1
  ];

  # Loaded with dlopen at runtime, so autoPatchelf cannot see the need for
  # them from the ELF headers alone.
  runtimeDependencies = [
    udev
    libGL
    vulkan-loader
  ];

  # The Qt shims are dlopened only when the platform theme is Qt, and the
  # musl reference comes from a statically linked helper. Neither is needed on
  # a GTK desktop, and neither can be satisfied from nixpkgs' glibc world.
  autoPatchelfIgnoreMissingDeps = [
    "libc.musl-x86_64.so.1"
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  unpackCmd = "dpkg-deb -x $curSrc source";
  sourceRoot = "source";
  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share
    cp -r "${srcDir}" "$out/share/${pname}"
    cp -r usr/share/icons $out/share/ 2>/dev/null || true

    # chrome-sandbox wants setuid root, which a store path can never be. The
    # sandbox is provided by the kernel's user namespaces on NixOS instead, so
    # remove it rather than ship a binary that aborts on launch.
    rm -f "$out/share/${pname}/chrome-sandbox"

    install -Dm444 usr/share/applications/${desktopName}.desktop \
      $out/share/applications/${desktopName}.desktop

    # Some ship an absolute /opt path in Exec (which does not exist here);
    # others already use a bare command name. Rewrite either to our wrapper.
    substituteInPlace $out/share/applications/${desktopName}.desktop \
      --replace-quiet '"/${srcDir}/${exeName}"' "${binName}" \
      --replace-quiet '/${srcDir}/${exeName}' "${binName}"

    runHook postInstall
  '';

  # gappsWrapperArgs is filled in by wrapGAppsHook3; wrapping by hand here
  # would drop the GSettings and GDK_PIXBUF paths it sets up.
  postFixup = ''
    makeWrapper "$out/share/${pname}/${exeName}" "$out/bin/${binName}" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"
  '';

  meta = {
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = binName;
  }
  // meta;
}
