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

    binaryCaches = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add nixarchy.cachix.org and hyprland.cachix.org as substituters.
        Without them, enabling nixarchy means compiling a compositor.

        This is the one thing here that changes a machine without any chance
        of a conflict to warn you: substituters and trusted-public-keys are
        lists, so they merge silently into whatever you already trust. Set
        this to false if that is not a decision you want made for you --
        everything still builds, it just builds locally.
      '';
    };

    preinstalls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the desktop applications Omarchy ships preinstalled -- the set
        omarchy-install-preinstalls restores and Remove > Preinstalls takes
        away. Upstream has these on a fresh machine, so they are on here too.

        Six of upstream's thirteen cannot be here: obsidian is unfree, so it
        would abort the whole rebuild rather than fail on its own -- enable
        `apps.obsidian` for it instead -- and aether, cliamp, omacut, omacalc
        and omawrite are Omarchy's own applications, not packaged in nixpkgs.
        lazydocker is already a runtime dependency.

        Turning this off is the declarative Remove > Preinstalls.
      '';
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

      # hyprland.cachix.org covers Hyprland when the pinned commit is one
      # hyprwm built; nixarchy.cachix.org covers it when it is not, plus the
      # vendored Omarchy tree and the packages this flake builds itself.
      #
      # Behind an option rather than mkForce: these are lists, so they merge
      # into a user's existing trust with no conflict and no warning, which
      # makes them the only thing in this module that can change a machine
      # silently. See programs.nixarchy.binaryCaches.
      substituters = lib.mkIf cfg.binaryCaches [
        "https://nixarchy.cachix.org"
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = lib.mkIf cfg.binaryCaches [
        "nixarchy.cachix.org-1:05JOuIlsQOWY2/5DQMq7JEA1hwlhgvmMWowMfka8mMM="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE="
      ];
    };

    # One `programs` block rather than three scattered assignments: statix
    # flags a repeated top-level key, and it is right that they read better
    # together.
    programs = {
      hyprland = {
        # This block is deliberately NOT mkDefault, unlike everything else
        # here. Omarchy *is* Hyprland, so enabling nixarchy while disabling it
        # is a contradiction rather than a preference -- and NixOS' own
        # hyprland module already defines `package` at mkDefault priority, so
        # matching that priority does not yield to the user, it ties with
        # nixpkgs and fails with "defined multiple times". Overriding these
        # means lib.mkForce, which is the honest signal for replacing the
        # compositor an entire desktop is written against.
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
      ])
      ++ lib.optionals cfg.preinstalls (
        with pkgs;
        [
          # omarchy-install-preinstalls, minus the six that cannot be here.
          pinta
          libreoffice
          xournalpp
          obs-studio
          moonlight-qt
          kdePackages.kdenlive

          # install/omarchy-base.packages. The GUIs manual sends people to
          # Disks for formatting and SMART, and sushi is what makes Space
          # preview a file in Nautilus without opening it.
          gnome-disk-utility
          sushi
        ]
      );
    };

    # install/config/*.sh and install/config/enable-services.sh, expressed as
    # options instead of the imperative scripts upstream runs once at install.
    # Every enable here is mkDefault. Nixarchy is a desktop, but it is a
    # NixOS module before it is a distribution, and someone adding it to a
    # machine they already run should not have to fight it: without mkDefault,
    # a laptop on TLP, a GNOME user on GDM, a podman user, anyone on
    # systemd-networkd or PulseAudio got an evaluation failure and had to
    # mkForce their way out one option at a time. Their setting wins now, and
    # they lose only the feature that depended on it.
    services = {
      # SDDM only if nothing else is already greeting. A machine that already
      # has GDM, LightDM, greetd or ly does not want a second display manager
      # -- NixOS gives it two definitions of displayManager.generic.execCmd
      # and refuses to build, which is a baffling error to meet when all you
      # did was add a desktop. The existing greeter launches Omarchy's session
      # from wayland-sessions perfectly well; only the branded greeter is lost.
      #
      # mkDefault on top, so `sddm.enable = true` still forces the issue.
      displayManager.sddm = {
        enable = lib.mkDefault (
          !(
            config.services.displayManager.gdm.enable
            || config.services.displayManager.ly.enable
            || config.services.xserver.displayManager.lightdm.enable
            || config.services.greetd.enable
          )
        );
        wayland.enable = lib.mkDefault true;

        # etc/sddm.conf.d/10-theme.conf. The theme itself rides in the package
        # at share/sddm/themes/omarchy, and /share/sddm is already one of the
        # paths linked into the system profile, so naming it here is enough.
        # Without this SDDM uses its own stock theme -- a blue gradient with a
        # placeholder avatar -- as the first screen of an Omarchy machine.
        theme = lib.mkDefault "omarchy";
      };

      # Left at mkDefault true rather than derived from services.pulseaudio:
      # NixOS' own graphical-desktop.nix already turns PipeWire on for any
      # graphical session, so deriving `false` here fights nixpkgs instead of
      # yielding to the user, and conflicts with that definition. A PulseAudio
      # user hits nixpkgs' assertion with or without nixarchy; that one is not
      # ours to resolve.
      pipewire = {
        enable = lib.mkDefault true;
        alsa.enable = lib.mkDefault true;
        alsa.support32Bit = lib.mkDefault true;
        pulse.enable = lib.mkDefault true;
        jack.enable = lib.mkDefault true;
      };

      # install/config/locate.sh
      locate.enable = lib.mkDefault true;

      # cups, cups-browsed, avahi and nss-mdns are all in base.packages
      printing.enable = lib.mkDefault true;
      avahi = {
        enable = lib.mkDefault true;
        nssmdns4 = lib.mkDefault true;
        openFirewall = lib.mkDefault true;
      };

      # gnome-keyring + libsecret, and the gvfs backends nautilus needs
      gnome.gnome-keyring.enable = lib.mkDefault true;
      gvfs.enable = lib.mkDefault true;
      udisks2.enable = lib.mkDefault true;

      # power-profiles-daemon is in base.packages, and NixOS asserts that it
      # and TLP cannot both be on. Same reasoning as pipewire above: a laptop
      # already running TLP never sets this, so mkDefault alone left the
      # assertion firing. omarchy-powerprofiles-set stops working, which is
      # the honest consequence of choosing the other power daemon.
      power-profiles-daemon.enable = lib.mkDefault (!config.services.tlp.enable);

      # The bar's battery widget and the power panel both read UPower over
      # DBus, and omarchy-powerprofiles-set autodetect gates on its OnBattery
      # property. That read is `2>/dev/null` with a fallback, so without the
      # daemon it does not fail -- it silently concludes you are on AC and
      # never switches to power-saver.
      upower.enable = lib.mkDefault true;
    };

    # The anchor ~/.XCompose includes. That file is written once at first
    # login and never rewritten, so it cannot name a store path: this one is
    # regenerated with the system and always points at the current package.
    environment.etc."omarchy/xcompose".source = "${cfg.package}/share/omarchy/default/xcompose";

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
    virtualisation.docker.enable = lib.mkDefault true;

    networking = {
      # install/config/firewall.sh (upstream uses ufw)
      firewall.enable = lib.mkDefault true;
      networkmanager.enable = lib.mkDefault true;
    };

    # install/config/lockscreen-pam.sh
    security.pam.services.hyprlock = { };

    # bin/omarchy-brightness-display-ddc talks to monitors over i2c
    hardware.i2c.enable = lib.mkDefault true;

    boot.plymouth.enable = lib.mkDefault true;

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
      enable = lib.mkDefault true;
      # xdg-desktop-portal-gtk is in upstream's base.packages. A portal is
      # registered, not merely installed, so it belongs here rather than in
      # the package's runtimeDeps. The hyprland portal comes from
      # programs.hyprland.portalPackage above.
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };
  };
}
