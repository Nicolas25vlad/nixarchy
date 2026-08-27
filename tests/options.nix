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

  broken = pkgs.lib.filterAttrs (_: c: !(c.on && !c.off)) cases;

  report = pkgs.lib.concatStringsSep "\n" (
    pkgs.lib.mapAttrsToList (
      name: c: "  ${name}: on=${builtins.toString c.on} off=${builtins.toString c.off}"
    ) cases
  );
in
pkgs.runCommand "nixarchy-options" { inherit report; } (
  if broken == { } then
    ''
      echo "$report"
      echo "every option adds what it should and removes it again"
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
