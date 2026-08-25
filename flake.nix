{
  description = "Nixarchy - Omarchy, vendored for NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    systems.url = "github:nix-systems/default-linux";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Omarchy 4.x configures Hyprland through the Lua API that landed in
    # 0.55; nixpkgs is still on 0.54.3.
    #
    # Pinned to a COMMIT, not the v0.56.2 tag, because that tag does not build
    # against its own flake.lock: its CMakeLists asks for
    # `find_package(glaze 7...<8)` while nix/overlays.nix feeds it the
    # glaze 8.0.0 from its locked nixpkgs. find_package fails, CMake falls
    # back to cloning glaze over the network, and the sandbox has none.
    # Upstream dropped the version bound after tagging, and v0.56.2 is the
    # newest tag, so there is no fixed tag to move to.
    #
    # A commit is just as reproducible as a tag. Bump it deliberately; never
    # track a branch here, or `nix flake update` could break the bar on its
    # own while the Lua bindings are still moving.
    #
    # Deliberately NOT `inputs.nixpkgs.follows = "nixpkgs"`: hyprwm asks
    # consumers not to override it, and doing so forfeits their binary cache
    # and rebuilds the compositor from source. See nix.settings in
    # modules/nixos.nix for the matching substituter.
    hyprland.url = "github:hyprwm/Hyprland/0bd11c7a04a63d2785abd53363f09d552175d67d";

    omarchy = {
      url = "github:basecamp/omarchy/v4.0.1";
      flake = false;
    };

    # Zen is not in nixpkgs and upstream maintains its own flake, which tracks
    # Zen's releases far more closely than a derivation here ever would.
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      home-manager,
      hyprland,
      omarchy,
      zen-browser,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;
      eachSystem = lib.genAttrs (import systems);
      pkgsFor = eachSystem (
        system:
        import nixpkgs {
          localSystem = system;
          overlays = [ self.overlays.default ];
        }
      );

      omarchyVersion = "4.0.1";
    in
    {
      overlays.default = final: _prev: {
        # Apps Omarchy offers that nixpkgs does not carry. Packaged here so a
        # NixOS user gets the same menu Arch users do, rather than a menu with
        # holes in it.
        nixarchy-apps =
          let
            mkElectronDeb = final.callPackage ./pkgs/apps/electron-deb.nix { };
            mkUpdateScript = final.callPackage ./pkgs/apps/update-script.nix { };
          in
          {
            # One updater per pinned package. `nix run .#update-all` runs the
            # lot; CI runs it weekly and opens a PR. These exist so that
            # tracking upstream is a bot's job rather than a maintainer's --
            # the 29 apps that come from nixpkgs already update themselves
            # when a user runs `nix flake update`.
            updaters = {
              once = mkUpdateScript {
                pname = "once";
                file = "pkgs/apps/once.nix";
                repo = "basecamp/once";
                artefacts = {
                  "x86_64-linux" = "https://github.com/basecamp/once/releases/download/v@version@/once-linux-amd64";
                  "aarch64-linux" = "https://github.com/basecamp/once/releases/download/v@version@/once-linux-arm64";
                };
              };
              t3code = mkUpdateScript {
                pname = "t3code";
                file = "pkgs/apps/t3code.nix";
                repo = "pingdotgg/t3code";
                artefacts.appimage = "https://github.com/pingdotgg/t3code/releases/download/v@version@/T3-Code-@version@-x86_64.AppImage";
              };
              voxtype = mkUpdateScript {
                pname = "voxtype";
                file = "pkgs/apps/voxtype.nix";
                repo = "peteonrails/voxtype";
                artefacts = builtins.listToAttrs (
                  map
                    (v: {
                      name = v;
                      value = "https://github.com/peteonrails/voxtype/releases/download/v@version@/voxtype-@version@-linux-x86_64-${v}";
                    })
                    [
                      "avx2"
                      "avx512"
                      "onnx-avx2"
                      "onnx-avx512"
                      "osd"
                      "osd-gtk4"
                      "audio-bridge"
                    ]
                );
              };
            };

            once = final.callPackage ./pkgs/apps/once.nix { };
            t3code = final.callPackage ./pkgs/apps/t3code.nix { };
            voxtype = final.callPackage ./pkgs/apps/voxtype.nix { };
            grok-bot = final.callPackage ./pkgs/apps/grok-bot.nix {
              inherit mkElectronDeb;
            };
            openai-codex-desktop = final.callPackage ./pkgs/apps/openai-codex-desktop.nix {
              inherit mkElectronDeb;
            };
          };

        omarchy = final.callPackage ./pkgs/omarchy {
          src = omarchy;
          version = omarchyVersion;
          # The compositor the Lua config is written against, not nixpkgs'.
          inherit (hyprland.packages.${final.stdenv.hostPlatform.system}) hyprland;
        };
      };

      packages = eachSystem (system: {
        default = self.packages.${system}.omarchy;
        inherit (pkgsFor.${system}) omarchy;

        inherit (pkgsFor.${system}.nixarchy-apps)
          once
          t3code
          grok-bot
          openai-codex-desktop
          voxtype
          ;

        # Re-exported so programs.nixarchy.apps.zen resolves like any other
        # `ours` app, without every consumer needing the extra flake input.
        zen-browser = zen-browser.packages.${system}.default;

        # `nix run .#update-all` -- rewrites every pinned version and hash in
        # place. CI runs this weekly and opens a PR with the result.
        update-all = pkgsFor.${system}.writeShellApplication {
          name = "nixarchy-update-all";
          runtimeInputs = builtins.attrValues pkgsFor.${system}.nixarchy-apps.updaters;
          text = ''
            failed=""
            for u in ${
              lib.concatStringsSep " " (
                map (n: "update-${n}") (builtins.attrNames pkgsFor.${system}.nixarchy-apps.updaters)
              )
            }; do
              # One updater failing must not hide the others: a vendor moving a
              # URL should still leave the remaining bumps to review.
              "$u" || failed="$failed $u"
            done
            if [ -n "$failed" ]; then
              echo "failed:$failed" >&2
              exit 1
            fi
          '';
        };

        # Boot the smoke test: `nix run .#vm`
        vm = self.nixosConfigurations.vm.config.system.build.vm;

        # Every command the vendored scripts exec by name, in one prefix.
        # The bins are unwrapped on purpose, so an incomplete runtimeDeps list
        # produces a package that builds cleanly and then fails at the click
        # -- which is how `Command not found: xdg-terminal-exec` shipped.
        # CI builds this and asserts the binaries are actually in it.
        omarchy-runtime = pkgsFor.${system}.buildEnv {
          name = "omarchy-runtime";
          paths = pkgsFor.${system}.omarchy.passthru.runtimeDeps;
          ignoreCollisions = true;
        };
      });

      nixosModules = {
        default = self.nixosModules.nixarchy;
        nixarchy = import ./modules/nixos.nix inputs;
      };

      homeManagerModules = {
        default = self.homeManagerModules.nixarchy;
        nixarchy = import ./modules/home.nix inputs;
      };

      # Smoke-test VM. Not a daily driver -- it exists to prove the QuickShell
      # bar comes up against Hyprland's Lua config before any packaging effort
      # is spent on the long tail.
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          self.nixosModules.nixarchy
          home-manager.nixosModules.home-manager
          ./vm/configuration.nix
        ];
      };

      devShells = eachSystem (system: {
        default = pkgsFor.${system}.callPackage ./shell.nix { };
      });

      formatter = eachSystem (system: pkgsFor.${system}.nixfmt-tree);

      checks = eachSystem (system: {
        omarchy = self.packages.${system}.omarchy;
        inherit (self.packages.${system}) omarchy-runtime;

        # Drives a real session and reports what it logged. See tests/session.nix
        # for why neither a serial console nor the smoke-test VM can do this.
        session = import ./tests/session.nix {
          inherit inputs;
          pkgs = pkgsFor.${system};
        };
        vm-toplevel = self.nixosConfigurations.vm.config.system.build.toplevel;
      });
    };
}
