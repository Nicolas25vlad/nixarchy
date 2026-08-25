{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  docker,
  makeWrapper,
}:
let
  version = "0.3.1";
  # Hashes come from omarchy-pkgs' own PKGBUILD rather than from a local
  # download, so they are the same artefacts Omarchy ships on Arch.
  # Keyed by system so the updater can rewrite each hash by name; see
  # pkgs/apps/update-script.nix.
  hashes = {
    "x86_64-linux" = "ef1eaf151a83b16e39dbfed49fe29ab9b703db7a441a911517044c6256e2aa27";
    "aarch64-linux" = "5374276c0c83bb9b8c15adadb7250f70c5c1a37bfd3006c3b8b14bda14495dc9";
  };
  urls = {
    "x86_64-linux" = "https://github.com/basecamp/once/releases/download/v${version}/once-linux-amd64";
    "aarch64-linux" = "https://github.com/basecamp/once/releases/download/v${version}/once-linux-arm64";
  };
  sources = lib.mapAttrs (
    system: sha256:
    fetchurl {
      url = urls.${system};
      inherit sha256;
    }
  ) hashes;
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
