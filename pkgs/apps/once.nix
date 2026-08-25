{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  docker,
  makeWrapper,
}:
let
  version = "0.3.0";
  # Hashes come from omarchy-pkgs' own PKGBUILD rather than from a local
  # download, so they are the same artefacts Omarchy ships on Arch.
  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/basecamp/once/releases/download/v${version}/once-linux-amd64";
      sha256 = "0e4c385ee3da47eeee0827c5db2977b1440548f98477b040845a593f0062ad0f";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/basecamp/once/releases/download/v${version}/once-linux-arm64";
      sha256 = "5e7cc49ff24cf0b9f45393f9895dd9d502a901100508c91fc137ede45b8d8467";
    };
  };
in
stdenvNoCC.mkDerivation {
  pname = "once";
  inherit version;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "once: no binary published for ${stdenvNoCC.hostPlatform.system}");

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/once
    runHook postInstall
  '';

  # once drives docker for everything it does; without it on PATH the first
  # thing a user sees is a command-not-found from inside a TUI.
  postFixup = ''
    wrapProgram $out/bin/once --prefix PATH : ${lib.makeBinPath [ docker ]}
  '';

  meta = {
    description = "CLI and TUI for installing and managing self-hosted web applications";
    homepage = "https://github.com/basecamp/once";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "once";
  };
}
