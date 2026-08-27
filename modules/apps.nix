inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  apps = import ../data/apps.nix;

  # The command each app puts on PATH, so the menu can tell "you already have
  # this" from "you have not installed it".
  #
  # meta.mainProgram rather than the attribute name: it is right where the two
  # differ, and they differ often -- obs-studio puts `obs` on PATH, not
  # `obs-studio`. It is metadata, so this reads it without building anything.
  #
  # tryEval because an unfree package throws at *evaluation* when allowUnfree
  # is off, and spotify and obsidian are both unfree. Without it, adding this
  # would have broken evaluation for everyone who has not opted into unfree --
  # a far worse outcome than the dim row it is here to draw. Falling back to
  # the app's own name is the same guess omarchy-pkg-present already makes.
  appBinary =
    name: app:
    let
      path = lib.splitString "." (app.attr or name);
      probe = builtins.tryEval (
        let
          p = lib.attrByPath path null pkgs;
        in
        if p == null then null else (p.meta.mainProgram or null)
      );
    in
    if probe.success && probe.value != null then probe.value else name;

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
        # `ours` apps are ones nixpkgs does not carry and that nixarchy
        # packages itself; they live in the overlay's nixarchy-apps set.
        default =
          if app.ours or false then
            inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.${app.attr}
          else
            pkgs.${app.attr};
        defaultText = lib.literalExpression (
          if app.ours or false then "nixarchy.packages.\${system}.${app.attr}" else "pkgs.${app.attr}"
        );
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
    # the current full list is always at /etc/nixarchy/apps-template.nix.
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
  # ── The menu extension ──────────────────────────────────────────────────
  # Rewrites Omarchy's Install menu in place. Upstream reads exactly one file,
  # ~/.config/omarchy/extensions/omarchy-menu.jsonc, and merges it over the
  # defaults by id -- "Reuse an existing id to override/extend it" -- so no
  # patching or forking of the menu is needed. It is watched, so a rebuild
  # takes effect without restarting the shell.
  #
  # A failing `when:` hides a row outright (MenuModel.js isVisible); a
  # succeeding `disabled:` leaves it listed but dim and unselectable, which is
  # what upstream already uses for "you have this installed".
  # The override rows, as data. Deliberately WITHOUT label or icon: those are
  # copied from upstream's own menu at build time by the script below, so a
  # rename upstream follows through instead of being frozen into this repo.
  overrideSpec = pkgs.writeText "nixarchy-menu-overrides.json" (
    builtins.toJSON (
      {
        "install.package" = {
          # Upstream wears the Arch logo here; the generator would carry it
          # across untouched, since it only fills in what an override omits.
          icon = "󰉉";
          label = "Edit app selection";
          action = "omarchy-launch-editor $HOME/.config/nixarchy/apps.nix";
          description = "Every Omarchy app, as NixOS options";
        };
        "install.aur" = {
          when = "false";
        };

        # Upstream wears the Arch logo here and runs `pacman -Rns` on the
        # selection. This picks over the app selection instead, and only ever
        # edits ~/.config/nixarchy/apps.nix -- never the user's own NixOS
        # configuration, which nixarchy does not own.
        "remove.package" = {
          icon = "󰭌";
          label = "App";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-app-remove";
          description = "Deselect apps, then Apply changes to rebuild without them";
        };

        # Upstream's label is "Omarchy" and its action pulls a git checkout and
        # runs pacman. The action is already replaced (see pkgs/omarchy/nix-bin);
        # this is the label catching up with what it now does.
        "update.omarchy" = {
          icon = "󰭌";
          label = "Nixarchy";
          description = "nix flake update, then nixos-rebuild switch --flake";
        };

        # Omarchy's release channels are a pacman repository choice. Here the
        # version is whatever the flake's omarchy input is pinned to, so there
        # is nothing to switch. Switching nixpkgs between stable and unstable
        # would mean editing the user's own system flake, which nixarchy does
        # not own -- it owns the Omarchy installation and its applications.
        #
        # The children are hidden individually: hiding a parent keeps its rows
        # out of the menu tree, but they stay reachable through search and
        # `omarchy menu summon`.
        "update.channel" = {
          when = "false";
        };
        "update.channel.stable" = {
          when = "false";
        };
        "update.channel.rc" = {
          when = "false";
        };
        "update.channel.edge" = {
          when = "false";
        };
        "update.channel.dev" = {
          when = "false";
        };

        # The Arch wiki is the wrong manual on a NixOS host. All three wear
        # nf-linux-nixos (U+F1105), the snowflake -- the icon and label are
        # stated explicitly because the generator only carries upstream's
        # across when an override does not bring its own.
        "learn.arch" = {
          icon = "󱄅";
          label = "NixOS";
          action = "omarchy-launch-webapp 'https://wiki.nixos.org/'";
          description = "NixOS Wiki";
        };
        "learn.nixpkgs" = {
          icon = "󱄅";
          label = "Nixpkgs";
          action = "omarchy-launch-webapp 'https://search.nixos.org/packages'";
          description = "Search for a package";
        };
        "learn.nix-options" = {
          icon = "󱄅";
          label = "NixOS Options";
          action = "omarchy-launch-webapp 'https://search.nixos.org/options'";
          description = "Search NixOS configuration options";
        };
        "install.apply" = {
          icon = "";
          label = "Apply changes";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-apply";
          description = "Copy the selection into your flake and nixos-rebuild switch";
        };
      }
      // lib.listToAttrs (
        lib.mapAttrsToList (
          name: app:
          lib.nameValuePair app.menuId (
            if app ? unavailable then
              {
                disabled = "true";
                description = "Not available on NixOS — ${app.unavailable}";
              }
            else
              {
                action = "nixarchy-app-enable ${name}";
                # Dim when the app is in the selection *or* already on PATH.
                #
                # The second half is the case nixarchy could not see before: an
                # app the user installed themselves, in their own
                # systemPackages or home.packages, which the selection knows
                # nothing about. The row offered to install something they
                # already had, and taking it would have written a second
                # declaration for it.
                #
                # Remove rows deliberately do NOT gain this. They stay bound to
                # the selection, because deselecting is the only removal
                # nixarchy is allowed to perform -- an app that arrived from
                # the user's own configuration is not this menu's to take away.
                disabled =
                  "grep -qE '^[[:space:]]*${name}\\.enable' $HOME/.config/nixarchy/apps.nix"
                  + " || command -v ${appBinary name app} >/dev/null 2>&1";
                description = "Enable in ~/.config/nixarchy/apps.nix, then Apply changes";
              }
          )
        ) (lib.filterAttrs (_: a: a ? menuId) apps)
      )
      // cfg.menu.extraEntries
    )
  );

  # arch package name -> our app id. The generator uses this to find upstream's
  # remove.* rows, which identify their app by `omarchy-pkg-present <arch>` in
  # their `when`, and rewrite them to disable the app in the selection instead.
  archMap = pkgs.writeText "nixarchy-arch-map.json" (
    builtins.toJSON (
      lib.listToAttrs (
        lib.mapAttrsToList (name: app: lib.nameValuePair app.arch name) (
          lib.filterAttrs (_: a: a ? arch) available
        )
      )
    )
  );

  # Built with a script rather than string-concatenated in Nix, because it has
  # to read upstream's menu to carry each row's label and icon across.
  #
  # This is not cosmetic. MenuModel.js normalizes every entry before merging --
  # `label: value.label || id` and `icon: value.icon || ""` -- and then copies
  # ALL keys of the override over the default. So an override that omits a
  # label does not inherit upstream's; it replaces it with the raw id, and the
  # menu renders "install.ai.chatgpt" instead of "ChatGPT Desktop".
  menuExtension =
    pkgs.runCommand "nixarchy-omarchy-menu.jsonc"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        inherit overrideSpec archMap;
        upstreamMenu = "${cfg.package}/share/omarchy/default/omarchy/omarchy-menu.jsonc";
      }
      ''
        python3 - "$upstreamMenu" "$overrideSpec" "$archMap" "$out" <<'PY'
        import json, re, sys

        upstream_path, spec_path, archmap_path, out_path = sys.argv[1:5]

        def strip_jsonc(raw):
            # The same two transformations MenuModel.js applies.
            raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
            return re.sub(r",(\s*[}\]])", r"\1", raw)

        upstream = json.loads(strip_jsonc(open(upstream_path).read()))
        overrides = json.load(open(spec_path))
        arch_map = json.load(open(archmap_path))

        # Upstream's remove.* rows name their app only in their `when`, as
        # `omarchy-pkg-present <arch-package>`. Deriving the overrides from
        # that keeps them tracking upstream instead of being hand-listed here,
        # and means a row upstream adds is picked up on the next bump.
        for row_id, row in upstream.items():
            if not row_id.startswith("remove.") or row_id in overrides:
                continue
            m = re.search(r"omarchy-pkg-present\s+([a-z0-9._@+-]+)", str(row.get("when", "")))
            if not m:
                continue
            app = arch_map.get(m.group(1))
            if not app:
                continue
            overrides[row_id] = {
                "action": f"nixarchy-app-disable {app}",
                # Show the row only when the app is actually selected, which is
                # what upstream's `omarchy-pkg-present` meant.
                "when": (
                    "grep -qE '^[[:space:]]*" + app
                    + "\\.enable' $HOME/.config/nixarchy/apps.nix"
                ),
                "description": "Remove from your app selection, then Apply changes",
            }

        out = {}
        missing = []
        for row_id, override in overrides.items():
            base = upstream.get(row_id)
            if base is None and not {"label", "icon"} & set(override):
                # A row we target that upstream no longer ships, and we have no
                # name of our own for it -- worth failing on rather than
                # rendering a raw id in the menu.
                missing.append(row_id)
                continue
            merged = dict(override)
            # Carry across EVERY key the override does not state. MenuModel.js
            # normalizes an entry before merging -- label falls back to the id,
            # and every other field to "" -- and then copies all of the
            # override's keys over the default. So an override that omits a
            # key does not inherit upstream's, it blanks it: omitting `label`
            # renders the raw id, and omitting `action` makes the row do
            # nothing at all. Only a full row is safe to hand back.
            if base:
                for key, value in base.items():
                    if key not in merged and value not in ("", [], None):
                        merged[key] = value
            out[row_id] = merged

        if missing:
            sys.exit("upstream menu has no rows: " + ", ".join(sorted(missing)))

        header = (
            "// Generated by nixarchy. Managed declaratively -- edit\n"
            "// programs.nixarchy.menu.extraEntries rather than this file,\n"
            "// which is a read-only symlink into the Nix store.\n"
            "//\n"
            "// Labels and icons are copied verbatim from Omarchy's own menu.\n"
        )
        open(out_path, "w").write(header + json.dumps(out, indent=2, ensure_ascii=False) + "\n")
        print(f"menu extension: {len(out)} rows")
        PY
      '';

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

    menu.extraEntries = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      example = lib.literalExpression ''
        { "personal.notes" = { icon = "󰎞"; label = "Notes"; action = "omarchy-launch-editor ~/notes"; }; }
      '';
      description = ''
        Extra rows merged into Omarchy's menu, keyed by dotted id. Reuse an
        existing id to override it.

        Upstream reads a single extension file, so nixarchy manages it and this
        option is how to add your own rows -- editing the file directly would
        be overwritten on the next rebuild.
      '';
    };

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
        environment.etc = {
          "nixarchy/apps-template.nix".source = appsTemplate;
          "nixarchy/omarchy-menu.jsonc".source = menuExtension;
        };

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
              cfg.package # omarchy-notification-send
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

              # A menu pick runs with no terminal attached, so stdout goes
              # nowhere and the pick looks like it did nothing at all. Say so
              # on the desktop instead. -r keeps repeated picks replacing one
              # notification rather than stacking a wall of them.
              queued=$(grep -cE "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" || true)
              if command -v omarchy-notification-send >/dev/null 2>&1; then
                # --exec makes the notification clickable: nothing is built
                # until a rebuild runs, so the notification that says so is
                # also the way to start it.
                omarchy-notification-send -r 8471 -t 8000 -u normal \
                  "$id queued -- not installed yet" \
                  "$queued app(s) selected. Click here, or Install > Apply changes, to run nixos-rebuild." \
                  --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
              fi
              echo "enabled $id in $file ($queued queued)"
              echo "run 'nixarchy-apply' when you have picked everything you want"
            '';
          })

          # The inverse of nixarchy-app-enable: re-comments the line. It only
          # ever touches ~/.config/nixarchy/apps.nix -- never the user's own
          # NixOS configuration, which nixarchy does not own and must not
          # edit. An app stays installed until a rebuild runs.
          (pkgs.writeShellApplication {
            name = "nixarchy-app-disable";
            runtimeInputs = [
              pkgs.gnused
              pkgs.gnugrep
              pkgs.coreutils
              cfg.package
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              id="''${1:?usage: nixarchy-app-disable <app-id>}"

              [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

              if ! grep -qE "#@ $id([[:space:]]|\$)" "$file"; then
                echo "nixarchy: no app '$id' in $file" >&2
                exit 1
              fi

              if ! grep -qE "^[[:space:]]*$id\.enable" "$file"; then
                echo "$id is not enabled"
                exit 0
              fi

              # Comment the line back out, preserving its indentation.
              sed -i -E "/#@ $id([[:space:]]|\$)/ s/^([[:space:]]*)([^[:space:]#])/\1# \2/" "$file"

              queued=$(grep -cE "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" || true)
              if command -v omarchy-notification-send >/dev/null 2>&1; then
                omarchy-notification-send -r 8471 -t 8000 -u normal \
                  "$id removed from your selection" \
                  "$queued app(s) still selected. Click here to run nixos-rebuild and apply it." \
                  --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
              fi
              echo "disabled $id in $file ($queued still enabled)"
              echo "it stays installed until 'nixarchy-apply' rebuilds"
            '';
          })

          # An interactive picker over what is currently selected, for the
          # Remove > Package row. Upstream offers a fuzzy picker over installed
          # pacman packages; this is the same shape over the app selection.
          (pkgs.writeShellApplication {
            name = "nixarchy-app-remove";
            runtimeInputs = [
              pkgs.gnugrep
              pkgs.gnused
              pkgs.coreutils
              pkgs.fzf
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

              mapfile -t enabled < <(
                grep -oE "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" \
                  | sed -E 's/[[:space:]]*//; s/\.enable//'
              )
              if [ ''${#enabled[@]} -eq 0 ]; then
                echo "Nothing is selected. Install > Package lists what is available."
                exit 0
              fi

              chosen=$(printf '%s\n' "''${enabled[@]}" | fzf --multi \
                --prompt="remove > " \
                --header="tab to select several, enter to confirm") || exit 0
              [ -n "$chosen" ] || exit 0

              while IFS= read -r app; do
                [ -n "$app" ] && nixarchy-app-disable "$app"
              done <<< "$chosen"

              echo
              echo "Run 'nixarchy-apply' to rebuild without them."
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
