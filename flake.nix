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
  };

  outputs =
    {
      self,
      nixpkgs,
      systems,
      home-manager,
      hyprland,
      omarchy,
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
        vm-toplevel = self.nixosConfigurations.vm.config.system.build.toplevel;
      });
    };
}
