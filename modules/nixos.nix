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

    bashIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Source Omarchy's bash rc chain -- default/bash/{envs,shell,aliases,
        functions,init,inputrc} plus every file in default/bash/fns -- into
        interactive bash. This is what provides the shell functions the manual
        documents (compress, dip, hdl, tdl, iso2sd, worktree and tmux
        helpers), and it needs no patching here because every path in that
        chain resolves through OMARCHY_PATH, which this module already
        exports.

        Nothing in the desktop depends on it: the menus and bin/ call the
        omarchy-* executables directly, not these functions. It is on by
        default because it is a real part of Omarchy, but it is opinionated --
        it aliases `ls` to eza, `cd` to zoxide, `g` to git, and sets EDITOR
        and BROWSER -- so it is worth turning off if you bring your own shell
        config. It loads from /etc/bashrc, i.e. before ~/.bashrc, so anything
        you define yourself still wins.
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

    # One `programs` block rather than three scattered assignments: statix
    # flags a repeated top-level key, and it is right that they read better
    # together.
    programs = {
      hyprland = {
        enable = true;
        package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
        portalPackage =
          inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.xdg-desktop-portal-hyprland;
        # Omarchy's session and its user units are started through uwsm.
        withUWSM = true;
      };

      # mise is in Omarchy's base packages and its dev-env installers lean on
      # it heavily. It downloads prebuilt runtimes, which cannot run against
      # NixOS' non-standard loader, so it detects NixOS and falls back to
      # compiling from source -- which then fails, because there is no compiler
      # on the session PATH. mise's own message names the fix:
      #
      #   "The automatic all_compile=true default on NixOS caused python to
      #    compile from source. Enable nix-ld to use precompiled binaries"
      #
      # This is what makes `omarchy install dev-env` work rather than print a
      # wall of build errors.
      nix-ld.enable = lib.mkDefault true;

      # See programs.nixarchy.bashIntegration. This lands in /etc/bashrc, which
      # bash sources BEFORE ~/.bashrc, so a user's own aliases still win.
      #
      # The chain needs no patching: `default/bash/rc` resolves everything
      # through OMARCHY_PATH, exported above, and the two /usr paths it does
      # mention -- Arch's env-bootstrap and bash_completion -- are both behind
      # `[ -r ... ]` guards, and their jobs are already done by this module and
      # by NixOS respectively.
      bash.interactiveShellInit = lib.mkIf cfg.bashIntegration ''
        source ${cfg.package}/share/omarchy/default/bash/rc
      '';
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
      systemPackages = [
        cfg.package
      ]
      ++ cfg.package.passthru.runtimeDeps
      ++ (with pkgs; [
        # omarchy-theme-set-gnome applies the light/dark half of every theme
        # with `gsettings set org.gnome.desktop.interface`, and on Arch the
        # schemas it writes arrive as transitive dependencies. Nothing pulls
        # them into a NixOS system profile, so gsettings answered "No schemas
        # installed" and every one of those writes was a no-op -- which is why
        # a dark theme left GTK apps and Chromium in light mode.
        glib
        gsettings-desktop-schemas

        # install/omarchy-base.packages:46. GTK 3 has no Adwaita-dark of its
        # own; gnome-themes-extra is the package that supplies it, and it is
        # the exact name gsettings gets set to.
        gnome-themes-extra

        # install/omarchy-base.packages:147. Every theme's icons.theme names a
        # Yaru variant -- Yaru-magenta, Yaru-sage, Yaru-olive and so on -- so
        # without this the icon theme is set to something that does not exist.
        yaru-theme
        # Yaru inherits from Adwaita for anything it does not draw itself.
        adwaita-icon-theme

        # Omarchy sets a cursor size but never a cursor theme -- on Arch one
        # comes with the desktop packages. NixOS ships none, so Hyprland used
        # its own built-in pointer. Bibata is here rather than Yaru or Adwaita
        # because those ship a single cursor each, and the point is to follow
        # the theme: Ice is white for dark themes, Classic black for light.
        bibata-cursors
      ]);
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

      # The bar's battery widget and the power panel both read UPower over
      # DBus, and omarchy-powerprofiles-set autodetect gates on its OnBattery
      # property. That read is `2>/dev/null` with a fallback, so without the
      # daemon it does not fail -- it silently concludes you are on AC and
      # never switches to power-saver.
      upower.enable = true;
    };

    # glib looks for compiled schemas in $XDG_DATA_DIRS/glib-2.0/schemas, but
    # nixpkgs' glib setup hook relocates them to
    # share/gsettings-schemas/<name>/glib-2.0/schemas so that two packages
    # shipping schemas cannot collide -- and environment.pathsToLink does not
    # carry that path into the system profile at all. Installing the package is
    # therefore not enough to make it readable: without this, gsettings answers
    # "No schemas installed" and omarchy-theme-set-gnome writes nothing.
    environment.sessionVariables.XDG_DATA_DIRS = [
      "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
    ];

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
