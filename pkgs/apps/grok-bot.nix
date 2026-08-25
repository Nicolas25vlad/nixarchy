{
  lib,
  fetchurl,
  mkElectronDeb,
}:
let
  version = "0.24.0";
  commit = "302d75da596fc8d11ee0446a19b31c33c6676c2c";
in
mkElectronDeb {
  pname = "grok-bot";
  inherit version;
  src = fetchurl {
    url = "https://downloads.cursor.com/grokbot/stable/${commit}/linux/x64/Grok_Bot_${version}.deb";
    sha256 = "5fd091d63fa410717737797ae0b14967e4f1567cae201d10c834430e4807f32d";
  };
  srcDir = "opt/Grok Bot";
  exeName = "grok-bot";
  meta = {
    description = "Grok Bot desktop agent";
    homepage = "https://x.ai/bot";
    license = lib.licenses.unfree;
  };
}
