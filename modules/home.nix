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

        # The whole of config/, not a chosen two of it. Upstream's own docs
        # point at ~/.config/foot/foot.ini and ~/.config/starship.toml, and
        # omarchy-theme-set-foot, btop's color_theme and the tmux keybindings
        # all read from ~/.config -- so seeding only hypr and omarchy left
        # starship on its stock prompt, tmux without Omarchy's prefix and
        # keybindings, and foot and btop unthemed.
        seed_dir "${omarchyPath}/config" "${config.xdg.configHome}"

        # install/user/theme.sh. btop.conf asks for a theme named "current",
        # and omarchy-theme-set-templates renders btop.theme into the current
        # theme on every switch, so this one symlink is what makes btop follow
        # the theme. Dangling until the first theme is set, which is fine.
        run mkdir -p "${config.xdg.configHome}/btop/themes"
        run ln -snf \
          "${config.home.homeDirectory}/.local/state/omarchy/current/theme/btop.theme" \
          "${config.xdg.configHome}/btop/themes/current.theme"

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
          # PATH, not just the absolute path to the script: omarchy-theme-set
          # calls its siblings by bare name -- omarchy-theme-set-templates and
          # omarchy-theme-color among them -- and has no `set -e`. Without the
          # package on PATH they were simply not found and it carried on and
          # exited 0, so no template was ever rendered: the first-run theme had
          # no btop.theme, foot.ini, alacritty.toml or gum_env.lua at all.
          run env OMARCHY_PATH="${omarchyPath}" OMARCHY_THEME_HEADLESS=1 \
            PATH="${cfg.package}/bin:${lib.makeBinPath cfg.package.passthru.runtimeDeps}:$PATH" \
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
          "PATH=${cfg.package}/bin:${pkgs.glib}/bin:${pkgs.coreutils}/bin:/run/current-system/sw/bin:%h/.nix-profile/bin"
          "OMARCHY_PATH=${omarchyPath}"
        ];
        ExecStart = [
          "${cfg.package}/bin/omarchy-theme-set-gnome"
          "${cfg.package}/bin/omarchy-cursor-set"
        ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Omarchy's own extension point -- omarchy-theme-set ends with
    # `omarchy-hook theme-set`, which runs everything in this directory. Going
    # through it rather than replacing omarchy-theme-set-gnome means the cursor
    # follows a theme change without this repo owning a fork of that script.
    xdg.configFile."omarchy/hooks/theme-set.d/cursor" = {
      executable = true;
      text = ''
        #!/usr/bin/env bash
        exec ${cfg.package}/bin/omarchy-cursor-set
      '';
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
