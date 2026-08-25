inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
in
{
  imports = [ inputs.hyprland.nixosModules.default ];

  options.programs.nixarchy = {
    enable = lib.mkEnableOption "Nixarchy, the Omarchy desktop vendored for NixOS";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omarchy;
      defaultText = lib.literalExpression "pkgs.omarchy";
      description = "The vendored Omarchy tree providing OMARCHY_PATH.";
    };

    useHyprlandCache = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add hyprwm's binary cache. Nixarchy pins Hyprland to a tag newer than
        nixpkgs, so with this off the compositor is built from source.
      '';
    };

    defaultTheme = lib.mkOption {
      type = lib.types.str;
      default = "tokyo-night";
      example = "catppuccin";
      description = ''
        Theme seeded on first login. Not enforced afterwards: Omarchy switches
        themes at runtime by rewriting ~/.local/state/omarchy, and that state
        is deliberately left mutable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.hyprland.package.version or "0" >= "0.55";
        message = ''
          Nixarchy needs Hyprland >= 0.55 for the Lua config API that
          Omarchy 4.x is written against (hl.bind / hl.window_rule / hl.on).
          Use inputs.hyprland's package, not nixpkgs'.
        '';
      }
    ];

    # Carried by the module so that importing nixosModules.nixarchy is all a
    # consumer has to do -- without this, `pkgs.omarchy` only exists inside
    # this flake's own package set and every downstream config has to wire the
    # overlay up by hand.
    nixpkgs.overlays = [ inputs.self.overlays.default ];

    nix.settings = lib.mkIf cfg.useHyprlandCache {
      substituters = [ "https://hyprland.cachix.org" ];
      trusted-public-keys = [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="
      ];
    };

    programs.hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
      portalPackage =
        inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
      # Omarchy's session and its user units are started through uwsm.
      withUWSM = true;
    };

    environment = {
      # The single indirection point. bin/, shell/, themes/ and the Hyprland
      # Lua defaults are all resolved relative to this.
      sessionVariables.OMARCHY_PATH = "${cfg.package}/share/omarchy";
      variables.OMARCHY_DEFAULT_THEME = cfg.defaultTheme;

      # Omarchy's scripts are unwrapped by design (wrapping breaks the CLI's
      # metadata scan), so their dependencies have to be on the session PATH.
      systemPackages = [ cfg.package ] ++ cfg.package.passthru.runtimeDeps;
    };

    # install/config/*.sh and install/config/enable-services.sh, expressed as
    # options instead of the imperative scripts upstream runs once at install.
    services = {
      displayManager.sddm = {
        enable = true;
        wayland.enable = true;
      };

      pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        jack.enable = true;
      };

      # install/config/locate.sh
      locate.enable = true;

      # cups, cups-browsed, avahi and nss-mdns are all in base.packages
      printing.enable = true;
      avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };

      # gnome-keyring + libsecret, and the gvfs backends nautilus needs
      gnome.gnome-keyring.enable = true;
      gvfs.enable = true;
      udisks2.enable = true;

      # power-profiles-daemon is in base.packages
      power-profiles-daemon.enable = true;
    };

    # install/config/docker.sh
    virtualisation.docker.enable = true;

    networking = {
      # install/config/firewall.sh (upstream uses ufw)
      firewall.enable = true;
      networkmanager.enable = true;
    };

    # install/config/lockscreen-pam.sh
    security.pam.services.hyprlock = { };

    # bin/omarchy-brightness-display-ddc talks to monitors over i2c
    hardware.i2c.enable = true;

    boot.plymouth.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      font-awesome
    ];

    xdg.portal.enable = true;
  };
}
