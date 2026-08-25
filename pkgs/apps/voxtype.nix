{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  alsa-lib,
  curl,
  gtk4,
  gtk4-layer-shell,
  libGL,
  wayland,
}:
let
  version = "0.7.5";
  base = "https://github.com/peteonrails/voxtype/releases/download/v${version}";

  # CPU variants only. Upstream also ships Vulkan, CUDA 12/13 and MIGraphX
  # builds, but those resolve their ONNX Runtime provider .so files through
  # /proc/self/exe and expect to sit in a writable directory beside them; that
  # is a poor fit for a store path and a large download for a GPU this may not
  # have. A user who wants one can override this package.
  variants = {
    "avx2" = "18ae0510d0c964689f8c9b7119c0b9a45569985e82977dc4f1ef4d76fddd887c";
    "avx512" = "bdb7c11fd10c33c1581d8d62352af9e4e1fd2b8dac7e4a35aa4f2775fa2ddb68";
    "onnx-avx2" = "a0e8f1cd4fa422989e6c01be27f3732b874ff1c0b3322adc756c6a5ab94c6594";
    "onnx-avx512" = "19e1895490b77f6cf3869675c95876e7eafcde97efad7acd76189d10a699199a";
    "osd" = "c510388dff6a69b59055a1915830fee8e0cb5aafd8f065e3e382b78a84eebab7";
    "osd-gtk4" = "fed81695551cee95bb0fd376ec6dc49638b0fd714480504d78aa597b006a5952";
    "audio-bridge" = "7b6aaffba35459bc20474aefcc09c6afd8a6fa6c4eb0859fefc2a1bc42fc9c24";
  };

  fetchVariant =
    name: sha256:
    fetchurl {
      url = "${base}/voxtype-${version}-linux-x86_64-${name}";
      inherit sha256;
    };
  bins = lib.mapAttrs fetchVariant variants;
in
stdenv.mkDerivation {
  pname = "voxtype";
  inherit version;

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    curl
    gtk4
    gtk4-layer-shell
    stdenv.cc.cc.lib
  ];

  runtimeDependencies = [
    libGL
    wayland
  ];

  installPhase = ''
    runHook preInstall

    # All variants share one directory because the OSD binaries locate their
    # siblings by resolving /proc/self/exe and probing the parent directory.
    # /proc/self/exe follows symlinks to the real store path, so the bin/
    # symlinks below still land them here.
    mkdir -p $out/lib/voxtype
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: drv: "install -Dm755 ${drv} $out/lib/voxtype/voxtype-${name}") bins
    )}

    mkdir -p $out/bin
    ln -s $out/lib/voxtype/voxtype-osd $out/bin/voxtype-osd
    ln -s $out/lib/voxtype/voxtype-audio-bridge $out/bin/voxtype-audio-bridge

    runHook postInstall
  '';

  # Arch picks a variant in a post-install script by probing the CPU. There is
  # no post-install step here, so the choice is made at launch instead --
  # which is also correct for a closure shared between machines.
  postFixup = ''
    cat > $out/bin/voxtype <<EOF
    #!${stdenv.shell}
    # Prefer the AVX-512 build where the CPU has it, as upstream's installer
    # does. VOXTYPE_VARIANT overrides, e.g. VOXTYPE_VARIANT=avx2 for the
    # Whisper engine rather than ONNX.
    variant="\''${VOXTYPE_VARIANT:-}"
    if [ -z "\$variant" ]; then
      if grep -qm1 avx512 /proc/cpuinfo 2>/dev/null; then
        variant=onnx-avx512
      else
        variant=onnx-avx2
      fi
    fi
    exec "$out/lib/voxtype/voxtype-\$variant" "\$@"
    EOF
    chmod +x $out/bin/voxtype
  '';

  meta = {
    description = "Push-to-talk voice-to-text for Linux";
    homepage = "https://voxtype.io";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "voxtype";
  };
}
