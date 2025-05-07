{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/24.11";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... } @ inputs: {
    nixosConfigurations = {
      "spudbox-dev" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/spudbox-dev/hardware.nix
          ./environments/dev.nix
          ./configuration.nix
        ];
      };

      "spudbox-prod" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          sops-nix.nixosModules.sops
          ./environments/prod.nix
          ./configuration.nix
        ];
      };
    };
  };
}
