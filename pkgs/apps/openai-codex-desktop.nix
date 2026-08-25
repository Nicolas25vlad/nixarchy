{
  lib,
  fetchurl,
  mkElectronDeb,
}:
let
  version = "26.818.61809";
in
mkElectronDeb {
  pname = "openai-codex-desktop";
  inherit version;
  src = fetchurl {
    url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
    sha256 = "148qjjqmcpi2h94ijysmjfhmsq5dvbnxhl18qrsrkm6jvfk65fhv";
  };
  # Not under /opt like the others.
  srcDir = "usr/lib/chatgpt";
  exeName = "ChatGPT";
  binName = "chatgpt";
  desktopName = "chatgpt";
  meta = {
    description = "Official ChatGPT desktop app with Codex";
    homepage = "https://chatgpt.com/codex/";
    license = lib.licenses.unfree;
  };
}
