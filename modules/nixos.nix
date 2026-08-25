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
  imports = [
    inputs.hyprland.nixosModules.default
    (import ./apps.nix inputs)
  ];

  options.programs.nixarchy = {
    enable = lib.mkEnableOption "Nixarchy, the Omarchy desktop vendored for NixOS";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy;
      defaultText = lib.literalExpression "nixarchy.packages.\${system}.omarchy";
      description = "The vendored Omarchy tree providing OMARCHY_PATH.";
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

    nix.settings = {
      # nixarchy-apply runs `nixos-rebuild switch --flake`, so flakes are not
      # optional here. mkDefault leaves a user free to manage this themselves.
      experimental-features = lib.mkDefault [
        "nix-command"
        "flakes"
      ];

      # Without these, enabling nixarchy means compiling a compositor.
      # hyprland.cachix.org covers Hyprland when the pinned commit is one
      # hyprwm built; nixarchy.cachix.org covers it when it is not, plus the
      # vendored Omarchy tree and the packages this flake builds itself.
      # mkForce them away if you would rather trust neither.
      substituters = [
        "https://nixarchy.cachix.org"
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
        "nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM="
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

      # The replacement omarchy-update reads this. It is a plain script inside
      # the package with no way to see module options, and it is reached from
      # the shell's bar widget and notifications as well as the menu.
      sessionVariables.NIXARCHY_FLAKE = cfg.flake;

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

    # mise is in Omarchy's base packages and its dev-env installers lean on it
    # heavily. It downloads prebuilt runtimes, which cannot run against NixOS'
    # non-standard loader, so it detects NixOS and falls back to compiling from
    # source -- which then fails, because there is no compiler on the session
    # PATH. mise's own message names the fix:
    #
    #   "The automatic all_compile=true default on NixOS caused python to
    #    compile from source. Enable nix-ld to use precompiled binaries"
    #
    # This is what makes `omarchy install dev-env` work rather than print a
    # wall of build errors.
    programs.nix-ld.enable = lib.mkDefault true;

    boot.plymouth.enable = true;

    fonts.packages = [
      # Omarchy's own icon font travels inside the package, at
      # share/fonts/truetype/omarchy.ttf. Without it registered here the menu
      # button's U+E900 draws as tofu -- an empty box in the bar.
      cfg.package
    ]
    ++ (with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.jetbrains-mono
      font-awesome
    ]);

    xdg.portal = {
      enable = true;
      # xdg-desktop-portal-gtk is in upstream's base.packages. A portal is
      # registered, not merely installed, so it belongs here rather than in
      # the package's runtimeDeps. The hyprland portal comes from
      # programs.hyprland.portalPackage above.
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };
  };
}
