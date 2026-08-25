{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  apps = import ../data/apps.nix;

  available = lib.filterAttrs (_: a: !(a ? unavailable)) apps;
  unavailable = lib.filterAttrs (_: a: a ? unavailable) apps;

  # One submodule per app. `settings` only has somewhere to go when the app is
  # a NixOS module rather than a bare package, so it is only offered there --
  # a freeform attrset with no target is a trap, not a feature.
  appModule =
    name: app:
    {
      enable = lib.mkEnableOption "${app.label} (${app.category})";

      # No `extraConfig` option here on purpose. The file the template is
      # written to is itself a NixOS module, so arbitrary configuration can
      # sit directly beside the app selection -- strictly more capable than
      # an option, and without forcing the module system to read a freeform
      # attrset's structure to learn what this module defines, which is a
      # dependency cycle.
    }
    // lib.optionalAttrs (app ? attr) {
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.${app.attr};
        defaultText = lib.literalExpression "pkgs.${app.attr}";
        description = "Package used for ${app.label}. Override to pin or patch it.";
      };
    }
    // lib.optionalAttrs (app ? option) {
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        example = lib.literalExpression (
          if name == "tailscale" then ''{ useRoutingFeatures = "client"; }'' else "{ }"
        );
        description = ''
          Merged into `${lib.concatStringsSep "." app.option}`. ${app.note or ""}
        '';
      };
    };

  # Every definition below is emitted for EVERY app, with mkIf deferring the
  # condition. Filtering by `enable` first would make the set of attributes
  # this module defines depend on config -- and the module system has to know
  # which options a module defines in order to evaluate those options, so that
  # is a cycle. Static structure, lazy values.
  appModuleConfig = lib.mkMerge (
    lib.mapAttrsToList (
      name: app:
      lib.optionalAttrs (app ? option) (
        lib.mkIf cfg.apps.${name}.enable (
          lib.setAttrByPath app.option ({ enable = true; } // cfg.apps.${name}.settings)
        )
      )
    ) available
  );

  # A value, not a structure, so this one may read config freely.
  appPackages = lib.concatLists (
    lib.mapAttrsToList (
      name: app: lib.optional ((app ? attr) && cfg.apps.${name}.enable) cfg.apps.${name}.package
    ) available
  );

  needsUnfree = lib.any (name: (available.${name}.unfree or false) && cfg.apps.${name}.enable) (
    lib.attrNames available
  );

  # ── The template ────────────────────────────────────────────────────────
  # Written fully populated and fully commented out, so enabling an app is
  # uncommenting one line rather than knowing a nixpkgs attribute. The `#@ id`
  # marker on each line is what nixarchy-app-enable matches on: it survives the
  # user reformatting, reordering or annotating the file, which a line-number
  # or label match would not.
  categories = lib.unique (map (a: a.category) (lib.attrValues apps));

  templateRow =
    name: app:
    let
      notes = lib.filter (s: s != "") [
        (lib.optionalString (app.unfree or false) "unfree")
        # Collapsed to one line: a note with a newline in it would break out
        # of the `#` comment and make the generated file fail to parse.
        (lib.replaceStrings [ "\n" ] [ " " ] (app.note or ""))
      ];
      suffix = lib.optionalString (notes != [ ]) "  # ${lib.concatStringsSep " — " notes}";
    in
    "    # ${name}.enable = true;  #@ ${name}${suffix}\n"
    + lib.optionalString (app ? option) "    #   ${name}.settings = { };  #@ ${name}.settings\n";

  templateCategory =
    cat:
    let
      inCat = lib.filterAttrs (_: a: a.category == cat) available;
      rows = lib.concatStrings (lib.mapAttrsToList templateRow inCat);
    in
    lib.optionalString (inCat != { }) ''

        # ── ${cat} ${lib.concatStrings (lib.genList (_: "─") (60 - lib.stringLength cat))}
      ${rows}'';

  unavailableNote = lib.concatStrings (
    lib.mapAttrsToList (_: a: "#   ${a.label} — ${a.unavailable}\n") unavailable
  );

  appsTemplate = pkgs.writeText "nixarchy-apps.nix" ''
    # Applications available through the Omarchy menu, as NixOS configuration.
    #
    # Every app is listed and every line is commented out. Uncomment what you
    # want -- or pick it from the menu, which uncomments it for you -- then run
    #
    #     nixarchy-apply
    #
    # to copy this into your flake and `nixos-rebuild switch`. Enable as many as
    # you like before applying; nothing is built until you do.
    #
    # This file is yours. Nothing regenerates or overwrites it once created;
    # the current full list always lives next to it in apps.available.nix.
    #
    # The `#@ name` markers are how the menu finds a line to uncomment. Keep
    # them and you can reformat, reorder and annotate this file freely.
    { ... }:
    {
      programs.nixarchy.apps = {
    ${lib.concatStrings (map templateCategory categories)}  };
    }

    # Offered by the Omarchy menu but with no nixpkgs equivalent:
    ${unavailableNote}'';
in
{
  options.programs.nixarchy = {
    # Declared as individual options rather than one submodule holding them
    # all: evaluating an outer submodule's _module.freeformType forces config,
    # and config here defines programs.* for the module-backed apps, which is
    # a cycle. One option per app has no such wrapper to evaluate.
    apps = lib.mapAttrs (
      name: app:
      lib.mkOption {
        type = lib.types.submodule { options = appModule name app; };
        default = { };
        description = "${app.label} (${app.category}).";
      }
    ) available;

    flake = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      example = "/home/alice/nixos-config";
      description = ''
        Flake directory that `nixarchy-apply` copies the app selection into
        before rebuilding.

        A flake cannot read a file outside its own source tree, so the
        generated ~/.config/nixarchy/apps.nix has to be copied in rather than
        imported from $HOME. Import the copy from your flake:

            imports = [ ./nixarchy-apps.nix ];
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      appModuleConfig
      {
        warnings = lib.optional (needsUnfree && !(config.nixpkgs.config.allowUnfree or false)) ''
          nixarchy: an enabled app is unfree but nixpkgs.config.allowUnfree is
          not set, so the build will fail with a licence error. Set it, or add
          the app to nixpkgs.config.allowUnfreePredicate.
        '';

        # Exported so the Home Manager module can seed it, and so a user can
        # always diff their file against the current full list.
        environment.etc."nixarchy/apps-template.nix".source = appsTemplate;

        environment.systemPackages = [
          # Uncomments one app in ~/.config/nixarchy/apps.nix. Matching is on
          # the `#@ <id>` marker, not a line number or a label, so the file
          # survives being reformatted, reordered or annotated by hand.
          (pkgs.writeShellApplication {
            name = "nixarchy-app-enable";
            runtimeInputs = [
              pkgs.gnused
              pkgs.gnugrep
              pkgs.coreutils
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              id="''${1:?usage: nixarchy-app-enable <app-id>}"

              [ -f "$file" ] || { echo "no $file -- log in again to have it created" >&2; exit 1; }

              if ! grep -qE "#@ $id([[:space:]]|\$)" "$file"; then
                echo "nixarchy: no app '$id' in $file" >&2
                exit 1
              fi

              if grep -q "^[[:space:]]*$id\.enable" "$file"; then
                echo "$id is already enabled; run nixarchy-apply to build it"
                exit 0
              fi

              # Strip one leading '# ' from the marked line, nothing else.
              sed -i -E "/#@ $id([[:space:]]|\$)/ s/^([[:space:]]*)# ?/\1/" "$file"
              echo "enabled $id in $file"
              echo "run 'nixarchy-apply' when you have picked everything you want"
            '';
          })

          # Copies the selection into the flake and switches. Kept separate
          # from enabling so several apps can be picked before anything builds.
          (pkgs.writeShellApplication {
            name = "nixarchy-apply";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.gnugrep
              pkgs.nixos-rebuild
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              flake="''${NIXARCHY_FLAKE:-${cfg.flake}}"
              dest="$flake/nixarchy-apps.nix"

              [ -f "$file" ] || { echo "no $file" >&2; exit 1; }
              [ -d "$flake" ] || {
                echo "nixarchy: flake directory '$flake' does not exist." >&2
                echo "Set programs.nixarchy.flake, or export NIXARCHY_FLAKE." >&2
                exit 1
              }

              echo "Enabled apps:"
              grep -E "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" || echo "  (none)"
              echo

              # A flake cannot read a file outside its own tree, so the
              # selection is copied in rather than imported from $HOME.
              if [ -f "$dest" ] && diff -q "$file" "$dest" >/dev/null; then
                echo "$dest is already up to date."
              else
                cp "$file" "$dest"
                echo "copied selection -> $dest"
                echo "(import it from your flake: imports = [ ./nixarchy-apps.nix ];)"
              fi

              read -r -p "Build and switch now? [y/N] " reply
              case "$reply" in
                [yY]*) exec sudo nixos-rebuild switch --flake "$flake" ;;
                *) echo "Not switching. Run: sudo nixos-rebuild switch --flake $flake" ;;
              esac
            '';
          })
        ]
        ++ appPackages;
      }
    ]
  );
}
