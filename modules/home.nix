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

    seedUserConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Copy upstream's `config/` skeleton into ~/.config on first activation.

        These are copied, never symlinked. Omarchy expects the user to edit
        ~/.config/hypr/*.lua by hand, and `omarchy-theme-set` rewrites files
        under ~/.local/state/omarchy at runtime. Home Manager's read-only
        store symlinks would make both fail, so this seeds once and then
        stays out of the way -- existing files are never overwritten.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [ cfg.package ] ++ cfg.package.passthru.runtimeDeps;

      sessionVariables.OMARCHY_PATH = omarchyPath;

      # Seed, don't manage. See seedUserConfig above for why this is an
      # activation script and not `home.file`.
      activation.nixarchySeed = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.optionalString cfg.seedUserConfig ''
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

              # Omarchy's menu extension is generated, not seeded: it carries the
            # install-row rewrites, so it has to keep tracking the package. Add
            # your own rows with programs.nixarchy.menu.extraEntries.
            run mkdir -p "${config.xdg.configHome}/omarchy/extensions"
            if [ -e /etc/nixarchy/omarchy-menu.jsonc ]; then
              run ln -sfn /etc/nixarchy/omarchy-menu.jsonc \
                "${config.xdg.configHome}/omarchy/extensions/omarchy-menu.jsonc"
            fi

            # The app template. Seeded once and never touched again -- it is the
              # user's selection, and clobbering it would silently undo their picks.
              # The regenerated full list sits beside it as apps.available.nix, so a
              # newly packaged app is always discoverable with a diff.
              run mkdir -p "${config.xdg.configHome}/nixarchy"
              if [ -e /etc/nixarchy/apps-template.nix ]; then
                if [ ! -e "${config.xdg.configHome}/nixarchy/apps.nix" ]; then
                  run ${pkgs.coreutils}/bin/install -m600 /etc/nixarchy/apps-template.nix \
                    "${config.xdg.configHome}/nixarchy/apps.nix"
                fi
                run ${pkgs.coreutils}/bin/install -m444 /etc/nixarchy/apps-template.nix \
                  "${config.xdg.configHome}/nixarchy/apps.available.nix"
              fi

                # First-run theme. omarchy-theme-set is the only thing that may write
                # this tree; running it headless avoids poking a shell that is not up.
                if [ ! -e "${config.home.homeDirectory}/.local/state/omarchy/current/theme.name" ]; then
                  run env OMARCHY_PATH="${omarchyPath}" OMARCHY_THEME_HEADLESS=1 \
                    ${cfg.package}/bin/omarchy-theme-set "${cfg.defaultTheme}" || true
                fi
        ''
      );
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
