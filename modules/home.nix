inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  omarchyPath = "${cfg.package}/share/omarchy";
in
{
  options.programs.nixarchy = {
    enable = lib.mkEnableOption "the Omarchy user session";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.omarchy;
      defaultText = lib.literalExpression "nixarchy.packages.\${system}.omarchy";
      description = "The vendored Omarchy tree providing OMARCHY_PATH.";
    };

    defaultTheme = lib.mkOption {
      type = lib.types.str;
      default = "tokyo-night";
      description = "Theme applied on first login only. Switchable at runtime afterwards.";
    };

  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [ cfg.package ] ++ cfg.package.passthru.runtimeDeps;

      sessionVariables.OMARCHY_PATH = omarchyPath;

      # Seed, don't manage: these files are copied, never symlinked. Omarchy
      # expects the user to edit ~/.config/hypr/*.lua by hand and rewrites
      # ~/.local/state/omarchy at runtime, both of which Home Manager's
      # read-only store symlinks would break. Existing files are never
      # overwritten.
      activation.nixarchySeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        seed_dir() {
          local src="$1" dest="$2"
          [ -d "$src" ] || return 0
          run mkdir -p "$dest"
          # --no-clobber: a file the user has edited is theirs, not ours.
          run ${pkgs.coreutils}/bin/cp -rn --no-preserve=mode,ownership \
            "$src"/. "$dest"/ 2>/dev/null || true
        }

        seed_dir "${omarchyPath}/config/hypr"    "${config.xdg.configHome}/hypr"
        seed_dir "${omarchyPath}/config/omarchy" "${config.xdg.configHome}/omarchy"

        run mkdir -p "${config.home.homeDirectory}/.local/state/omarchy/current"

        # omarchy-branding-screensaver writes straight into this directory and
        # never creates it, so editing the screensaver text failed with
        # "E212: Can't open file for writing". Upstream's config skeleton does
        # not ship it either.
        run mkdir -p "${config.xdg.configHome}/omarchy/branding"

        # The menu extension is generated, not seeded: it carries the
        # install-row rewrites, so it has to keep tracking the package. Add
        # your own rows with programs.nixarchy.menu.extraEntries.
        run mkdir -p "${config.xdg.configHome}/omarchy/extensions"
        if [ -e /etc/nixarchy/omarchy-menu.jsonc ]; then
          run ln -sfn /etc/nixarchy/omarchy-menu.jsonc \
            "${config.xdg.configHome}/omarchy/extensions/omarchy-menu.jsonc"
        fi

        # The app selection. Seeded once and never touched again -- it holds
        # the user's picks, and clobbering it would silently undo them.
        # /etc/nixarchy/apps-template.nix always holds the current full list,
        # so a newly packaged app is discoverable with a diff against it.
        run mkdir -p "${config.xdg.configHome}/nixarchy"
        if [ ! -e "${config.xdg.configHome}/nixarchy/apps.nix" ] \
          && [ -e /etc/nixarchy/apps-template.nix ]; then
          run ${pkgs.coreutils}/bin/install -m600 /etc/nixarchy/apps-template.nix \
            "${config.xdg.configHome}/nixarchy/apps.nix"
        fi

        # First-run theme. omarchy-theme-set is the only thing that may write
        # this tree; running it headless avoids poking a shell that is not up.
        if [ ! -e "${config.home.homeDirectory}/.local/state/omarchy/current/theme.name" ]; then
          run env OMARCHY_PATH="${omarchyPath}" OMARCHY_THEME_HEADLESS=1 \
            ${cfg.package}/bin/omarchy-theme-set "${cfg.defaultTheme}" || true
        fi
      '';
    };

    # The first-run theme above is applied headless, which by design skips every
    # post-theme command -- including omarchy-theme-set-gnome, the one that
    # tells GTK and the settings portal whether this theme is light or dark.
    # Upstream never notices: on Arch that command runs during install with a
    # live session, and dconf keeps the answer forever after. Here the first
    # session would come up dark-themed with light GTK apps until the user
    # switched themes by hand.
    #
    # Unlike the shell below, this needs only the session bus, not a running
    # compositor, so a graphical-session unit is the right shape for it. It is
    # a no-op on every later login, because it writes what dconf already holds.
    systemd.user.services.omarchy-theme-gnome = {
      Unit = {
        Description = "Apply the current Omarchy theme's light/dark mode to GTK";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "oneshot";
        # omarchy-theme-set-gnome shells out to omarchy-theme-color and
        # gsettings, and a user unit does not inherit the login PATH.
        Environment = [
          "PATH=${cfg.package}/bin:${pkgs.glib}/bin:${pkgs.coreutils}/bin"
          "OMARCHY_PATH=${omarchyPath}"
        ];
        ExecStart = "${cfg.package}/bin/omarchy-theme-set-gnome";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # No systemd unit for the shell. Upstream starts it from Hyprland itself:
    #
    #   default/hypr/autostart.lua
    #   hl.on("hyprland.start", function() hl.exec_cmd("omarchy-launch-shell") end)
    #
    # A graphical-session.target unit runs before the compositor is up, and
    # omarchy-launch-shell responds to that by exiting 0 -- see its
    # compositor_alive() guard. The unit therefore "succeeded" while starting
    # nothing, and duplicated a launch Hyprland was already doing correctly.
  };
}
