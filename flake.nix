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
    # 0.55; nixpkgs is still on 0.54.3. Pinned to a tag rather than tracking
    # master because the Lua bindings are days old and still moving -- a
    # `nix flake update` should never be able to break the bar on its own.
    #
    # Deliberately NOT `inputs.nixpkgs.follows = "nixpkgs"`: hyprwm asks
    # consumers not to override it, and doing so forfeits their binary cache
    # and rebuilds the compositor from source. See nix.settings in
    # modules/nixos.nix for the matching substituter.
    hyprland.url = "github:hyprwm/Hyprland/v0.56.2";

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
        vm-toplevel = self.nixosConfigurations.vm.config.system.build.toplevel;
      });
    };
}
