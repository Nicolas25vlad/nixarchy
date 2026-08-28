{ inputs, pkgs }:
# The options that add or remove something, checked both ways.
#
# An option nobody turns off is an option nobody knows is broken. Each of
# these is on by default and covered in that state by some other check, so
# what is untested is the half a user reaches for when they do not want the
# default -- and that half is exactly what a refactor breaks quietly.
#
# Evaluated rather than booted. Every option here does its work by putting a
# package in a list or a line in a file, so evaluation is where the answer is;
# booting a VM to look would be slower and prove no more. That is not the case
# generally -- see tests/integration.nix for the bugs that only a build finds.
let
  system = pkgs.stdenv.hostPlatform.system;

  configWith =
    settings:
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        inputs.self.nixosModules.nixarchy
        {
          programs.nixarchy = {
            enable = true;
          }
          // settings;
        }
        {
          boot.loader.grub.device = "/dev/sda";
          fileSystems."/" = {
            device = "/dev/sda1";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    }).config;

  sessionNames =
    cfg: map (p: p.passthru.providedSessions or [ ]) cfg.services.displayManager.sessionPackages;

  hasOmarchySession = cfg: builtins.elem "omarchy" (pkgs.lib.flatten (sessionNames cfg));

  # Each case is (what it should look like on, what it should look like off).
  cases = {
    session = {
      on = hasOmarchySession (configWith {
        session = true;
      });
      off = hasOmarchySession (configWith {
        session = false;
      });
    };

    displayManager = {
      on = (configWith { displayManager = true; }).services.displayManager.sddm.enable;
      off = (configWith { displayManager = false; }).services.displayManager.sddm.enable;
    };

    binaryCaches = {
      on =
        builtins.elem "https://nixarchy.cachix.org"
          (configWith { binaryCaches = true; }).nix.settings.substituters;
      off =
        builtins.elem "https://nixarchy.cachix.org"
          (configWith { binaryCaches = false; }).nix.settings.substituters;
    };

    preinstalls = {
      # "Pinta", capitalised -- its pname is not the attribute name, and
      # matching the attribute name found nothing in either direction, which
      # this check reported as the option being broken. It was the probe.
      on =
        builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstalls = true; }).environment.systemPackages;
      off =
        builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstalls = false; }).environment.systemPackages;
    };

    # preinstallsExclude is the per-application half of preinstalls, and the
    # only removal path for an app the selection does not carry. Both ways:
    # Pinta is there by default and gone when named.
    preinstallsExclude = {
      on =
        !(builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstallsExclude = [ "pinta" ]; }).environment.systemPackages
        );
      off =
        !(builtins.any (p: (p.pname or "") == "Pinta")
          (configWith { preinstallsExclude = [ ]; }).environment.systemPackages
        );
    };

    # bootSplash, which is three-valued rather than a switch. The half that
    # matters is `force`: it has to beat a theme set at normal priority, which
    # is what stylix does and what sends people reaching for mkForce on
    # boot.plymouth.theme alone -- a build failure, because themePackages then
    # does not contain what the name points at.
    bootSplash = {
      on = (configWith { bootSplash = "force"; }).boot.plymouth.theme == "omarchy";
      off = (configWith { bootSplash = "off"; }).boot.plymouth.theme == "omarchy";
    };

    browserThemeUser = {
      # null is the default, so this one reads the other way round: the rules
      # appear when a user is named.
      on =
        builtins.any (r: pkgs.lib.hasInfix "chromium/policies" r)
          (configWith { browserThemeUser = "someone"; }).systemd.tmpfiles.rules;
      off =
        builtins.any (r: pkgs.lib.hasInfix "chromium/policies" r)
          (configWith { browserThemeUser = null; }).systemd.tmpfiles.rules;
    };
  };

  # Every Install row upstream offers, checked against what the selection
  # covers -- so a row added by an Omarchy bump cannot quietly go unmapped.
  #
  # The exceptions are listed rather than counted, because "how many are
  # unmapped" is a number that drifts silently and "which ones, and why" is
  # a decision someone made. Each of these is either not an application at
  # all, or a known gap the README names.
  # The menu file. Parsed in the builder rather than here: stripping JSONC
  # comments with string functions in Nix got the indented ones wrong and fed
  # builtins.fromJSON something that was still commented. Python has a parser;
  # this file does not need a second one.
  menuFile = "${(pkgs.extend inputs.self.overlays.default).omarchy}/share/omarchy/default/omarchy/omarchy-menu.jsonc";

  mappedRows = pkgs.lib.mapAttrsToList (_: a: a.menuId) (
    pkgs.lib.filterAttrs (_: a: a ? menuId) (import ../data/apps.nix)
  );

  # Rows that are actions rather than applications, plus the gaps the README
  # names. Fonts go through omarchy-install-font and the Arch-name map; the
  # four gaming rows and three frameworks are documented as needing a hand.
  notApps = [
    "install.aur"
    "install.package"
    "install.preinstalls"
    "install.style.background"
    "install.style.theme"
    "install.tui"
    "install.webapp"
    "install.windows"
    "install.service.chromium-account"
    "install.style.font.bitstream"
    "install.style.font.cascadia"
    "install.style.font.fira"
    "install.style.font.iosevka"
    "install.style.font.meslo"
    "install.style.font.victor"
    "install.ai.ollama"
    "install.gaming.battlenet"
    "install.gaming.geforce-now"
    "install.gaming.retro-launcher"
    "install.gaming.xbox-cloud"
    "install.development.docker-dbs"
    "install.development.elixir.phoenix"
    "install.development.php.laravel"
    "install.development.rails"
  ];

  broken = pkgs.lib.filterAttrs (_: c: !(c.on && !c.off)) cases;

  report = pkgs.lib.concatStringsSep "\n" (
    pkgs.lib.mapAttrsToList (
      name: c: "  ${name}: on=${builtins.toString c.on} off=${builtins.toString c.off}"
    ) cases
  );
in
pkgs.runCommand "nixarchy-options"
  {
    inherit report;
    inherit menuFile;
    omarchyPath = "${(pkgs.extend inputs.self.overlays.default).omarchy}/share/omarchy";
    mapped = pkgs.lib.concatStringsSep " " mappedRows;
    notApps = pkgs.lib.concatStringsSep " " notApps;
    nativeBuildInputs = [ pkgs.python3 ];
  }
  (
    if broken == { } then
      ''
        echo "$report"
        echo "every option adds what it should and removes it again"

        python3 ${./coverage.py}
        touch $out
      ''
    else
      ''
        echo "$report"
        echo "these options do not take effect both ways: ${pkgs.lib.concatStringsSep " " (builtins.attrNames broken)}" >&2
        echo "an option that cannot be turned off is not an option." >&2
        exit 1
      ''
  )
