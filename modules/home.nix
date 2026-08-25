_inputs:
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
      default = pkgs.omarchy;
      defaultText = lib.literalExpression "pkgs.omarchy";
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

          # First-run theme. omarchy-theme-set is the only thing that may write
          # this tree; running it headless avoids poking a shell that is not up.
          if [ ! -e "${config.home.homeDirectory}/.local/state/omarchy/current/theme.name" ]; then
            run env OMARCHY_PATH="${omarchyPath}" OMARCHY_THEME_HEADLESS=1 \
              ${cfg.package}/bin/omarchy-theme-set "${cfg.defaultTheme}" || true
          fi
        ''
      );
    };

    # default/systemd/user/*.service -- upstream ships 10 user units. Only the
    # shell supervisor is wired up here; the rest are opt-in until the smoke
    # test says which actually matter on NixOS.
    systemd.user.services.omarchy-shell = {
      Unit = {
        Description = "Omarchy QuickShell desktop shell";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.package}/bin/omarchy-launch-shell";
        Environment = [ "OMARCHY_PATH=${omarchyPath}" ];
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
